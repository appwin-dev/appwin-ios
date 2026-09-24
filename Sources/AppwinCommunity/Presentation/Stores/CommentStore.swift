import Foundation

/// Comment thread of one post. Instantiated per detail screen: two posts
/// opened in a row have no reason to share state.
@MainActor
final class CommentStore: ObservableObject {
    @Published private(set) var comments: [CommunityComment] = []
    @Published private(set) var isLoading = false
    @Published private(set) var isSending = false
    @Published private(set) var errorMessage: String?

    /// Comment being replied to, `nil` for a root comment.
    @Published var replyingTo: CommunityComment?

    private let repo: CommunityRepository
    private let postId: String
    private var offset = 0
    private let pageSize = CommunityPagination.commentsPageSize
    private(set) var hasMore = true

    init(repo: CommunityRepository, postId: String) {
        self.repo = repo
        self.postId = postId
    }

    func load() async {
        isLoading = true
        errorMessage = nil
        offset = 0
        do {
            let page = try await repo.comments(postId: postId, limit: pageSize, offset: 0)
            comments = page
            offset = page.count
            hasMore = page.count == pageSize
        } catch {
            errorMessage = String(describing: error)
        }
        isLoading = false
    }

    func loadMore() async {
        guard hasMore, !isLoading else { return }
        do {
            let page = try await repo.comments(postId: postId, limit: pageSize, offset: offset)
            let known = Set(comments.map(\.id))
            comments.append(contentsOf: page.filter { !known.contains($0.id) })
            offset += page.count
            hasMore = page.count == pageSize
        } catch {
            errorMessage = String(describing: error)
        }
    }

    /// Posts a comment, or a reply when `replyingTo` is set.
    ///
    /// Returns `true` when the server accepted, which the caller uses to clear
    /// the input. A `false` leaves the text in place rather than losing it.
    @discardableResult
    func send(body: String, media: [CommunityMedia] = []) async -> Bool {
        let trimmed = body.trimmingCharacters(in: .whitespacesAndNewlines)
        guard (!trimmed.isEmpty || !media.isEmpty), !isSending else { return false }

        isSending = true
        defer { isSending = false }

        do {
            let created = try await repo.createComment(
                postId: postId,
                body: trimmed,
                parentCommentId: replyingTo?.id,
                media: media
            )
            insert(created)
            replyingTo = nil
            errorMessage = nil
            return true
        } catch {
            errorMessage = String(describing: error)
            return false
        }
    }

    /// Files a comment in the right place: at the end of the thread when it is
    /// a root comment, under its parent when it is a reply.
    private func insert(_ comment: CommunityComment) {
        guard let parentId = comment.parentCommentId else {
            comments.append(comment)
            return
        }
        if let index = comments.firstIndex(where: { $0.id == parentId }) {
            comments[index] = comments[index].appendingReply(comment)
            return
        }
        // Parent may still be a nested reply id: attach under that reply's root.
        if let index = comments.firstIndex(where: { root in
            root.replies.contains(where: { $0.id == parentId })
        }) {
            comments[index] = comments[index].appendingReply(comment)
            return
        }
        // Parent outside the current page: add it flat rather than lose
        // it. It settles into place on the next load.
        comments.append(comment)
    }

    func delete(commentId: String) async {
        do {
            try await repo.deleteComment(commentId: commentId)
            comments.removeAll { $0.id == commentId }
            // A deleted reply must disappear from its parent too.
            comments = comments.map { $0.removingReply(id: commentId) }
        } catch {
            errorMessage = String(describing: error)
        }
    }

    /// Optimistic toggle, same logic as the feed.
    func toggleReaction(commentId: String, kind: CommunityReactionKind) async {
        if let index = comments.firstIndex(where: { $0.id == commentId }) {
            await toggleReaction(atRootIndex: index, commentId: commentId, kind: kind)
            return
        }
        // Nested reply: patch inside its parent.
        for (rootIndex, root) in comments.enumerated() {
            guard let replyIndex = root.replies.firstIndex(where: { $0.id == commentId }) else {
                continue
            }
            let previous = root.replies[replyIndex]
            let optimistic = optimisticReactionState(
                myReaction: previous.myReaction,
                reactionCounts: previous.reactionCounts,
                likeCount: previous.likeCount,
                kind: kind
            )
            var replies = root.replies
            replies[replyIndex] = previous.applying(
                myReaction: optimistic.myReaction,
                topReactions: optimistic.topReactions,
                reactionCounts: optimistic.reactionCounts,
                likeCount: optimistic.likeCount
            )
            comments[rootIndex] = root.applying(replies: replies)
            do {
                let result = try await repo.reactToComment(commentId: commentId, kind: kind)
                guard let currentRoot = comments[safe: rootIndex],
                      let currentReply = currentRoot.replies.firstIndex(where: { $0.id == commentId })
                else { return }
                var next = currentRoot.replies
                next[currentReply] = next[currentReply].applying(
                    myReaction: result.myReaction.flatMap(CommunityReactionKind.init(rawValue:)),
                    topReactions: (result.topReactions ?? []).compactMap(CommunityReactionKind.init(rawValue:)),
                    reactionCounts: (result.reactionCounts ?? []).compactMap { $0.toDomain() },
                    likeCount: result.likeCount
                )
                comments[rootIndex] = currentRoot.applying(replies: next)
            } catch {
                comments[rootIndex] = root
            }
            return
        }
    }

    private func toggleReaction(
        atRootIndex index: Int,
        commentId: String,
        kind: CommunityReactionKind
    ) async {
        let previous = comments[index]
        let optimistic = optimisticReactionState(
            myReaction: previous.myReaction,
            reactionCounts: previous.reactionCounts,
            likeCount: previous.likeCount,
            kind: kind
        )
        comments[index] = previous.applying(
            myReaction: optimistic.myReaction,
            topReactions: optimistic.topReactions,
            reactionCounts: optimistic.reactionCounts,
            likeCount: optimistic.likeCount
        )
        do {
            let result = try await repo.reactToComment(commentId: commentId, kind: kind)
            guard let current = comments.firstIndex(where: { $0.id == commentId }) else { return }
            comments[current] = comments[current].applying(
                myReaction: result.myReaction.flatMap(CommunityReactionKind.init(rawValue:)),
                topReactions: (result.topReactions ?? []).compactMap(CommunityReactionKind.init(rawValue:)),
                reactionCounts: (result.reactionCounts ?? []).compactMap { $0.toDomain() },
                likeCount: result.likeCount
            )
        } catch {
            if let current = comments.firstIndex(where: { $0.id == commentId }) {
                comments[current] = previous
            }
        }
    }

}

private extension Array {
    subscript(safe index: Int) -> Element? {
        indices.contains(index) ? self[index] : nil
    }
}

// MARK: - Partial copies

extension CommunityComment {
    func applying(
        myReaction: CommunityReactionKind?? = nil,
        topReactions: [CommunityReactionKind]? = nil,
        reactionCounts: [CommunityReactionCount]? = nil,
        likeCount: Int? = nil,
        replies: [CommunityComment]? = nil,
        replyCount: Int? = nil
    ) -> CommunityComment {
        CommunityComment(
            id: id,
            postId: postId,
            parentCommentId: parentCommentId,
            author: author,
            body: body,
            media: media,
            translatedBody: translatedBody,
            sourceLanguage: sourceLanguage,
            likeCount: likeCount ?? self.likeCount,
            replyCount: replyCount ?? self.replyCount,
            myReaction: myReaction ?? self.myReaction,
            topReactions: topReactions ?? self.topReactions,
            reactionCounts: reactionCounts ?? self.reactionCounts,
            canEdit: canEdit,
            canDelete: canDelete,
            isPendingReview: isPendingReview,
            replies: replies ?? self.replies,
            createdAt: createdAt,
            editedAt: editedAt
        )
    }

    /// `replyCount` is the server-side total, not `replies.count`: a thread of
    /// 10 replies only ships 2 inline. It is incremented explicitly, otherwise
    /// "see the 8 other replies" would go wrong.
    func appendingReply(_ reply: CommunityComment) -> CommunityComment {
        applying(replies: replies + [reply], replyCount: replyCount + 1)
    }

    func removingReply(id: String) -> CommunityComment {
        guard replies.contains(where: { $0.id == id }) else { return self }
        return applying(
            replies: replies.filter { $0.id != id },
            replyCount: max(0, replyCount - 1)
        )
    }
}
