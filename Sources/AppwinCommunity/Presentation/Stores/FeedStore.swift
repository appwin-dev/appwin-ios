import Foundation

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
    /// Batched and flushed shortly after appear (and on leave / refresh): waiting
    /// only for `onDisappear` dropped views when the member stayed on the feed.
    private var pendingViews: Set<String> = []
    private var flushViewsTask: Task<Void, Never>?

    var hasMore: Bool { nextCursor != nil }

    init(repo: CommunityRepository) {
        self.repo = repo
    }

    deinit {
        flushViewsTask?.cancel()
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
                limit: CommunityPagination.feedPageSize
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
    ///
    /// Always pass the session's current group: `currentGroupId` can lag behind
    /// a tab change that is still loading, and would refresh the wrong feed.
    func refresh(groupId: String? = nil) async {
        if let groupId {
            currentGroupId = groupId
        }
        await flushViews()
        do {
            let page = try await repo.feed(
                groupId: currentGroupId,
                authorProfileId: nil,
                sort: sort,
                cursor: nil,
                limit: CommunityPagination.feedPageSize
            )
            posts = page.items
            nextCursor = page.nextCursor
            errorMessage = nil
        } catch is CancellationError {
            // Pull-to-refresh cancels when the gesture ends early: keep the
            // current list rather than surfacing a spurious error.
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
                limit: CommunityPagination.feedPageSize
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

    /// Inserts a freshly created post using the same order as the API feed:
    /// pinned first, then newest. A non-pinned post lands under the pinned block.
    func prepend(_ post: CommunityPost) {
        posts.removeAll { $0.id == post.id }
        if post.isPinned {
            posts.insert(post, at: 0)
            return
        }
        let insertAt = posts.firstIndex(where: { !$0.isPinned }) ?? posts.endIndex
        posts.insert(post, at: insertAt)
    }

    func replace(_ post: CommunityPost) {
        guard let index = posts.firstIndex(where: { $0.id == post.id }) else { return }
        // Moved out of the filtered group: drop it rather than leave a stale card.
        if let currentGroupId, post.groupId != currentGroupId {
            posts.remove(at: index)
            return
        }
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

        let optimistic = optimisticReactionState(
            myReaction: previous.myReaction,
            reactionCounts: previous.reactionCounts,
            likeCount: previous.likeCount,
            kind: kind
        )
        posts[index] = previous.applying(
            myReaction: optimistic.myReaction,
            topReactions: optimistic.topReactions,
            reactionCounts: optimistic.reactionCounts,
            likeCount: optimistic.likeCount
        )

        do {
            let result = try await repo.reactToPost(postId: postId, kind: kind)
            guard let current = posts.firstIndex(where: { $0.id == postId }) else { return }
            posts[current] = posts[current].applying(
                myReaction: result.myReaction.flatMap(CommunityReactionKind.init(rawValue:)),
                topReactions: (result.topReactions ?? []).compactMap(CommunityReactionKind.init(rawValue:)),
                    reactionCounts: (result.reactionCounts ?? []).compactMap { $0.toDomain() },
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
        scheduleFlushViews()
    }

    /// Sends the accumulated batch. Silent: this is telemetry, and failing it
    /// visibly would tell the member nothing useful.
    func flushViews() async {
        // Cancel a pending debounce without canceling the network call itself
        // (see `performFlushViews`).
        flushViewsTask?.cancel()
        flushViewsTask = nil
        await performFlushViews()
    }

    private func scheduleFlushViews() {
        flushViewsTask?.cancel()
        flushViewsTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: 800_000_000)
            guard !Task.isCancelled else { return }
            // Call perform directly: `flushViews()` would cancel *this* task and
            // abort the POST under `try?`, so views never reached the server.
            await self?.performFlushViews()
        }
    }

    private func performFlushViews() async {
        flushViewsTask = nil
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
        topReactions: [CommunityReactionKind]? = nil,
        reactionCounts: [CommunityReactionCount]? = nil,
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
            topReactions: topReactions ?? self.topReactions,
            reactionCounts: reactionCounts ?? self.reactionCounts,
            canEdit: canEdit,
            canDelete: canDelete,
            isPendingReview: isPendingReview,
            publishedAt: publishedAt,
            editedAt: editedAt
        )
    }
}
