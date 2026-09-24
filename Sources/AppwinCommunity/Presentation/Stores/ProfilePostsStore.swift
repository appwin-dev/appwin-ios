import Foundation
import Combine

/// Paginated posts by a single author, for the profile Publications tab.
@MainActor
final class ProfilePostsStore: ObservableObject {
    @Published private(set) var posts: [CommunityPost] = []
    @Published private(set) var isLoading = false
    @Published private(set) var isLoadingMore = false
    @Published private(set) var errorMessage: String?

    private var authorProfileId: String?
    private var nextCursor: String?
    private var hasMore = true

    func load(authorProfileId: String) async {
        self.authorProfileId = authorProfileId
        isLoading = true
        errorMessage = nil
        nextCursor = nil
        hasMore = true
        defer { isLoading = false }
        do {
            let page = try await Factory.repository().feed(
                groupId: nil,
                authorProfileId: authorProfileId,
                sort: .recent,
                cursor: nil,
                limit: CommunityPagination.feedPageSize
            )
            posts = page.items
            nextCursor = page.nextCursor
            hasMore = page.nextCursor != nil
        } catch {
            errorMessage = String(describing: error)
            posts = []
        }
    }

    func loadMore() async {
        guard let authorProfileId, hasMore, !isLoadingMore, let cursor = nextCursor else { return }
        isLoadingMore = true
        defer { isLoadingMore = false }
        do {
            let page = try await Factory.repository().feed(
                groupId: nil,
                authorProfileId: authorProfileId,
                sort: .recent,
                cursor: cursor,
                limit: CommunityPagination.feedPageSize
            )
            let known = Set(posts.map(\.id))
            posts.append(contentsOf: page.items.filter { !known.contains($0.id) })
            nextCursor = page.nextCursor
            hasMore = page.nextCursor != nil
        } catch {
            errorMessage = String(describing: error)
        }
    }

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
            let result = try await Factory.repository().reactToPost(postId: postId, kind: kind)
            if let i = posts.firstIndex(where: { $0.id == postId }) {
                posts[i] = posts[i].applying(
                    myReaction: result.myReaction.flatMap(CommunityReactionKind.init(rawValue:)),
                    topReactions: (result.topReactions ?? []).compactMap(CommunityReactionKind.init(rawValue:)),
                    reactionCounts: (result.reactionCounts ?? []).compactMap { $0.toDomain() },
                    likeCount: result.likeCount
                )
            }
        } catch {
            if let i = posts.firstIndex(where: { $0.id == postId }) {
                posts[i] = previous
            }
        }
    }

    func patchCommentCount(postId: String, delta: Int) {
        guard let index = posts.firstIndex(where: { $0.id == postId }) else { return }
        let post = posts[index]
        posts[index] = post.applying(commentCount: max(0, post.commentCount + delta))
    }

    func remove(postId: String) {
        posts.removeAll { $0.id == postId }
    }

    func replace(_ post: CommunityPost) {
        guard let index = posts.firstIndex(where: { $0.id == post.id }) else { return }
        posts[index] = post
    }
}
