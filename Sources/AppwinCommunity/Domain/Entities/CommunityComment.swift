import Foundation

/// Comment under a post. One level of reply only: `replies` is always empty on
/// a reply, and never nested deeper. Tapping Reply on a reply still works -
/// the server re-parents it under the root so the thread stays flat.
///
/// `replyCount` can exceed `replies.count` - the server only ships the first
/// replies inline, and the rest load on demand.
struct CommunityComment: Identifiable, Equatable {
    let id: String
    let postId: String
    let parentCommentId: String?
    let author: CommunityAuthor?
    let body: String
    let media: [CommunityMedia]
    let translatedBody: String?
    let sourceLanguage: String?
    let likeCount: Int
    let replyCount: Int
    let myReaction: CommunityReactionKind?
    /// Up to 3 most frequent reactions (any reader), for the summary row.
    let topReactions: [CommunityReactionKind]
    /// Full per-kind breakdown (sorted by volume), for the tap-to-detail sheet.
    let reactionCounts: [CommunityReactionCount]
    let canEdit: Bool
    let canDelete: Bool
    let isPendingReview: Bool
    let replies: [CommunityComment]
    let createdAt: Date
    let editedAt: Date?

    /// Replies still to load, beyond those delivered inline.
    var hiddenReplyCount: Int { max(0, replyCount - replies.count) }
}
