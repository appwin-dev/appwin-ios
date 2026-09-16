import Foundation

/// Comment under a post. One level of reply only: `replies` is always empty on
/// a reply, and never nested deeper.
///
/// `replyCount` can exceed `replies.count` - the server only ships the first
/// replies inline, and the rest load on demand.
struct CommunityComment: Identifiable, Equatable {
    let id: String
    let postId: String
    let parentCommentId: String?
    let author: CommunityAuthor?
    let body: String
    let translatedBody: String?
    let sourceLanguage: String?
    let likeCount: Int
    let replyCount: Int
    let myReaction: CommunityReactionKind?
    let canEdit: Bool
    let canDelete: Bool
    let isPendingReview: Bool
    let replies: [CommunityComment]
    let createdAt: Date
    let editedAt: Date?

    /// Replies still to load, beyond those delivered inline.
    var hiddenReplyCount: Int { max(0, replyCount - replies.count) }
}
