import Foundation
import AppwinCore

/// Feed state: pagination, optimistic reactions, view counting.
@MainActor
final class FeedStore: ObservableObject {
    @Published private(set) var posts: [CommunityPost] = []
    @Published private(set) var isLoading = false
    @Published private(set) var isLoadingMore = false
    @Published private(set) var errorMessage: String?

    private let repo: CommunityRepository
    private var nextCursor: String?
    private var currentGroupId: String?
    private var sort: CommunityFeedSort = .recent

    /// Posts seen but not yet reported to the server.
    ///
    /// One call per scrolled post would be absurd, so they accumulate and go
    /// out in a batch when the member leaves the screen. Losing the last batch
    /// to an app kill does not matter for a view counter.
    private var pendingViews: Set<String> = []

    var hasMore: Bool { nextCursor != nil }

    /// Shared realtime hub (ADR-0028), Community's first realtime client: the
    /// feed refreshes when another member posts or reacts.
    private let realtimeHub: RealtimeHub?
    private var realtimeSubs: [UUID] = []

    init(repo: CommunityRepository) {
        self.repo = repo
        self.realtimeHub = AppwinCore.realtimeHub()
        if let hub = realtimeHub {
            let resync: @Sendable () -> Void = { [weak self] in
                Task { @MainActor in await self?.refresh() }
            }
            for event in [
                "community.post.created",
                "community.post.updated",
                "community.post.deleted",
                "community.reaction.changed",
            ] {
                realtimeSubs.append(hub.on(event: event) { _ in resync() })
            }
            hub.start()
        }
    }

    deinit {
        // `off` is thread-safe, so it can be called off the MainActor.
        for id in realtimeSubs { realtimeHub?.off(id) }
    }

    /// First page, or a full reload after a tab change.
    ///
    /// The feed reloads on every open: a member coming back wants what has
    /// happened since, not the state from an hour ago.
    func load(groupId: String?, sort: CommunityFeedSort = .recent) async {
        currentGroupId = groupId
        self.sort = sort
        isLoading = true
        errorMessage = nil
        do {
            let page = try await repo.feed(
                groupId: groupId,
                authorProfileId: nil,
                sort: sort,
                cursor: nil,
                limit: 20
            )
            posts = page.items
            nextCursor = page.nextCursor
        } catch {
            errorMessage = String(describing: error)
        }
        isLoading = false
    }

    /// Pull to refresh: reloads without clearing the list first, so the content
    /// does not flicker under the finger.
    func refresh() async {
        do {
            let page = try await repo.feed(
                groupId: currentGroupId,
                authorProfileId: nil,
                sort: sort,
                cursor: nil,
                limit: 20
            )
            posts = page.items
            nextCursor = page.nextCursor
            errorMessage = nil
        } catch {
            errorMessage = String(describing: error)
        }
    }

    /// Next page. Ignored when nothing is left or a load is already running.
    func loadMore() async {
        guard let cursor = nextCursor, !isLoadingMore else { return }
        isLoadingMore = true
        do {
            let page = try await repo.feed(
                groupId: currentGroupId,
                authorProfileId: nil,
                sort: sort,
                cursor: cursor,
                limit: 20
            )
            // Deduplicate: a post published between two pages can shift the
            // cursor window and reappear, and a duplicate `Identifiable` would
            // crash SwiftUI's `List`.
            let known = Set(posts.map(\.id))
            posts.append(contentsOf: page.items.filter { !known.contains($0.id) })
            nextCursor = page.nextCursor
        } catch {
            errorMessage = String(describing: error)
        }
        isLoadingMore = false
    }

    // MARK: - Mutations

    func prepend(_ post: CommunityPost) {
        posts.insert(post, at: 0)
    }

    func replace(_ post: CommunityPost) {
        guard let index = posts.firstIndex(where: { $0.id == post.id }) else { return }
        posts[index] = post
    }

    func remove(postId: String) {
        posts.removeAll { $0.id == postId }
    }

    /// Toggles a reaction, applied optimistically.
    ///
    /// The counter moves at once: a like that waits for the round trip makes
    /// the app feel broken. The server returns the resulting state, which is
    /// applied over it, and a failure restores exactly the previous state.
    func toggleReaction(postId: String, kind: CommunityReactionKind) async {
        guard let index = posts.firstIndex(where: { $0.id == postId }) else { return }
        let previous = posts[index]

        let isRemoving = previous.myReaction == kind
        posts[index] = previous.applying(
            myReaction: isRemoving ? nil : kind,
            likeCount: previous.likeCount + (isRemoving ? -1 : (previous.myReaction == nil ? 1 : 0))
        )

        do {
            let result = try await repo.reactToPost(postId: postId, kind: kind)
            guard let current = posts.firstIndex(where: { $0.id == postId }) else { return }
            posts[current] = posts[current].applying(
                myReaction: result.myReaction.flatMap(CommunityReactionKind.init(rawValue:)),
                likeCount: result.likeCount
            )
        } catch {
            if let current = posts.firstIndex(where: { $0.id == postId }) {
                posts[current] = previous
            }
        }
    }

    /// Applies the comment count after one is added from the detail screen.
    func bumpCommentCount(postId: String, by delta: Int) {
        guard let index = posts.firstIndex(where: { $0.id == postId }) else { return }
        let post = posts[index]
        posts[index] = post.applying(commentCount: max(0, post.commentCount + delta))
    }

    func voteOnPoll(postId: String, optionId: String) async {
        guard let index = posts.firstIndex(where: { $0.id == postId }) else { return }
        let previous = posts[index]
        do {
            let poll = try await repo.voteOnPoll(postId: postId, optionId: optionId)
            if let current = posts.firstIndex(where: { $0.id == postId }) {
                posts[current] = posts[current].applying(poll: poll)
            }
        } catch {
            if let current = posts.firstIndex(where: { $0.id == postId }) {
                posts[current] = previous
            }
        }
    }

    // MARK: - Views

    func markVisible(postId: String) {
        pendingViews.insert(postId)
    }

    /// Sends the accumulated batch. Silent: this is telemetry, and failing it
    /// visibly would tell the member nothing useful.
    func flushViews() async {
        guard !pendingViews.isEmpty else { return }
        let batch = Array(pendingViews)
        pendingViews.removeAll()
        try? await repo.trackViews(postIds: batch)
    }
}

// MARK: - Partial copies

extension CommunityPost {
    /// Copy with a few fields replaced.
    ///
    /// Swift generates no `copyWith` for structs of `let`s. Rather than turning
    /// every field into a `var` and opening the door to stray mutation, we
    /// expose only the copies the feed needs.
    func applying(
        myReaction: CommunityReactionKind?? = nil,
        likeCount: Int? = nil,
        commentCount: Int? = nil,
        translatedBody: String?? = nil,
        poll: CommunityPoll?? = nil
    ) -> CommunityPost {
        CommunityPost(
            id: id,
            groupId: groupId,
            groupName: groupName,
            author: author,
            body: body,
            translatedBody: translatedBody ?? self.translatedBody,
            sourceLanguage: sourceLanguage,
            media: media,
            poll: poll ?? self.poll,
            isPinned: isPinned,
            hasAdminTag: hasAdminTag,
            likeCount: likeCount ?? self.likeCount,
            commentCount: commentCount ?? self.commentCount,
            viewCount: viewCount,
            myReaction: myReaction ?? self.myReaction,
            canEdit: canEdit,
            canDelete: canDelete,
            isPendingReview: isPendingReview,
            publishedAt: publishedAt,
            editedAt: editedAt
        )
    }
}
