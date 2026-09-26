import Foundation

/// Profile as other members can see it.
///
/// `isMe` is resolved server-side, which saves the SDK comparing ids to know
/// whether to show Edit or Report.
struct CommunityProfile: Identifiable, Equatable {
    let id: String
    let nickname: String
    let bio: String?
    let avatarUrl: URL?
    let role: CommunityMemberRole
    let isTeam: Bool
    /// `true` while neither the host app nor the member has supplied an identity.
    let isAnonymous: Bool
    let postCount: Int
    let commentCount: Int
    let receivedReactionCount: Int
    /// How long they have been in the community.
    let joinedAt: Date
    let isMe: Bool
    /// A hard restriction. A shadow ban never declares itself - that is the
    /// whole point - so it does not surface here.
    let isBanned: Bool

    static let placeholder = CommunityProfile(
        id: "",
        nickname: "",
        bio: nil,
        avatarUrl: nil,
        role: .member,
        isTeam: false,
        isAnonymous: true,
        postCount: 0,
        commentCount: 0,
        receivedReactionCount: 0,
        joinedAt: Date(),
        isMe: true,
        isBanned: false
    )
}

/// Thematic group of the feed, shown as a tab.
struct CommunityGroup: Identifiable, Equatable {
    let id: String
    let name: String
    let description: String?
    let emoji: String?
    let imageUrl: URL?
    let isDefault: Bool
/// Resolved server-side from the group's policy **and** the reader's role.
    let canPost: Bool
    let postCount: Int
}

/// The `bootstrap` response: the whole first screen in one round trip.
struct CommunityBootstrap: Equatable {
    let config: CommunityConfig
    let groups: [CommunityGroup]
    let profile: CommunityProfile
    let unreadNotificationCount: Int
}

/// Transactional in-app notification ("X commented on your post").
struct CommunityNotification: Identifiable, Equatable {
    let id: String
    let type: CommunityNotificationType
    let actor: CommunityNotificationActor?
    let targetType: String
    let targetId: String
    /// Post to open on tap, including when the target is a comment.
    let postId: String?
    let excerpt: String?
    let isRead: Bool
    let createdAt: Date
}

struct CommunityNotificationActor: Equatable {
    let id: String
    let nickname: String
    let avatarUrl: URL?
}

enum CommunityNotificationType: String, Equatable {
    case postComment = "post_comment"
    case commentReply = "comment_reply"
    case postReaction = "post_reaction"
    case commentReaction = "comment_reaction"
    case pollVote = "poll_vote"
    case contentRemoved = "content_removed"
    case adminPost = "admin_post"
}

/// Report reasons offered to the member, in display order.
enum CommunityReportReason: String, Equatable, CaseIterable {
    case spam
    case harassment
    case hateSpeech = "hate_speech"
    case sexualContent = "sexual_content"
    case violence
    case misinformation
    case offTopic = "off_topic"
    case other
}
