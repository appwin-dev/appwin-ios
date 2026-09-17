// Domain entity shaped by what the feed displays, not by the API.
//
// Types propres : `Date` (pas String ISO), `URL` (pas String), enums (pas
// The server's moderation fields (`moderationScore`, `reportCount`, …) do not
// surface here: the SDK does nothing with them, and carrying them would give
// them a chance of ending up on screen.

import Foundation

struct CommunityPost: Identifiable, Equatable {
    let id: String
    let groupId: String
    let groupName: String
    /// `nil` when the author was erased with no frozen name.
    let author: CommunityAuthor?
    let body: String
    /// Translation in the reader's language, `nil` when useless or unavailable.
    let translatedBody: String?
    let sourceLanguage: String?
    let media: [CommunityMedia]
    let poll: CommunityPoll?
    let isPinned: Bool
    /// Team badge on the post, independent of the author's role.
    let hasAdminTag: Bool
    let likeCount: Int
    let commentCount: Int
    let viewCount: Int
    /// The reader's reaction, `nil` when they have not reacted.
    let myReaction: CommunityReactionKind?
    let canEdit: Bool
    let canDelete: Bool
    /// Visible to the author alone: held by moderation, or shadow banned.
    let isPendingReview: Bool
    let publishedAt: Date
    let editedAt: Date?
}

/// Author as displayed under a piece of content. The bare minimum: any extra
/// field is one more to invalidate when the profile changes.
struct CommunityAuthor: Equatable {
    let id: String
    let nickname: String
    let avatarUrl: URL?
    let role: CommunityMemberRole
    /// Team badge under the name, driven by the studio rather than the role.
    let isTeam: Bool
}

enum CommunityMemberRole: String, Equatable {
    case member, moderator, admin
}

struct CommunityPoll: Equatable {
    let options: [CommunityPollOption]
    let totalVotes: Int
    let myOptionId: String?
}

struct CommunityPollOption: Identifiable, Equatable {
    let id: String
    let text: String
    let voteCount: Int
}

/// Image attached to a post. `width` and `height` let the space be reserved
/// before loading, so nothing jumps while scrolling.
struct CommunityMedia: Identifiable, Equatable {
    var id: String { url.absoluteString }
    let url: URL
    let width: Int?
    let height: Int?
    let alt: String?

    /// Width-to-height ratio, `nil` when the dimensions are missing.
    var aspectRatio: CGFloat? {
        guard let width, let height, height > 0 else { return nil }
        return CGFloat(width) / CGFloat(height)
    }
}
