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
    private let pageSize = 20
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
    /// the input. A `false` leaves the text in place rather than losing it.
    @discardableResult
    func send(body: String) async -> Bool {
        let trimmed = body.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, !isSending else { return false }

        isSending = true
        defer { isSending = false }

        do {
            let created = try await repo.createComment(
                postId: postId,
                body: trimmed,
                parentCommentId: replyingTo?.id
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
        guard let index = comments.firstIndex(where: { $0.id == parentId }) else {
            // Parent outside the current page: add it flat rather than lose
            // it. It settles into place on the next load.
            comments.append(comment)
            return
        }
        let parent = comments[index]
        comments[index] = parent.appendingReply(comment)
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
        guard let index = comments.firstIndex(where: { $0.id == commentId }) else { return }
        let previous = comments[index]

        let isRemoving = previous.myReaction == kind
        comments[index] = previous.applying(
            myReaction: isRemoving ? nil : kind,
            likeCount: previous.likeCount
                + (isRemoving ? -1 : (previous.myReaction == nil ? 1 : 0))
        )

        do {
            let result = try await repo.reactToComment(commentId: commentId, kind: kind)
            guard let current = comments.firstIndex(where: { $0.id == commentId }) else { return }
            comments[current] = comments[current].applying(
                myReaction: result.myReaction.flatMap(CommunityReactionKind.init(rawValue:)),
                likeCount: result.likeCount
            )
        } catch {
            if let current = comments.firstIndex(where: { $0.id == commentId }) {
                comments[current] = previous
            }
        }
    }
}

// MARK: - Partial copies

extension CommunityComment {
    func applying(
        myReaction: CommunityReactionKind?? = nil,
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
            translatedBody: translatedBody,
            sourceLanguage: sourceLanguage,
            likeCount: likeCount ?? self.likeCount,
            replyCount: replyCount ?? self.replyCount,
            myReaction: myReaction ?? self.myReaction,
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
