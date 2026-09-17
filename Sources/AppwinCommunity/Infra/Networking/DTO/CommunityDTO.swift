// Network DTOs to domain entities.
//
// Strict boundary: the rest of the SDK never sees a DTO. ISO dates, URLs as
// strings and enums as strings are converted here, once, and anything
// unreadable degrades cleanly rather than failing the whole page.
// unreadable degrades cleanly rather than failing the whole page.

import Foundation

// MARK: - Shared parsing

/// Tolerant ISO-8601 decoder.
///
/// The server returns dates with fractional seconds on some fields and without
/// on others. `ISO8601DateFormatter` is strict about that, so two attempts beat
/// an empty page.
enum CommunityDateParser {
    // `nonisolated(unsafe)` is deliberate: both formatters are configured in
    // their initialiser closure and never mutated, and `date(from:)` is
    // thread-safe on Apple platforms. Recreating one per decoded post would
    // cost far more than a feed page justifies - `ISO8601DateFormatter` is
    // notoriously expensive to instantiate.
    private nonisolated(unsafe) static let withFractional: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return f
    }()

    private nonisolated(unsafe) static let plain: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime]
        return f
    }()

    static func parse(_ raw: String?) -> Date? {
        guard let raw else { return nil }
        return withFractional.date(from: raw) ?? plain.date(from: raw)
    }
}

private func parseURL(_ raw: String?) -> URL? {
    guard let raw, !raw.isEmpty else { return nil }
    return URL(string: raw)
}

// MARK: - Config

struct CommunityConfigDTO: Decodable {
    let theme: ThemeDTO
    let features: FeaturesDTO
    let limits: LimitsDTO
    let context: ContextDTO
    let version: Int

    struct ThemeDTO: Decodable {
        let primary: String
        let primaryForeground: String
        /// Optional: a config saved before the field existed has no value.
        let autoGradient: Bool?
        let headerTitle: String?
        let headerTitleVisible: Bool?
        let fontFamily: String
        let fontFamilyName: String?
        let fontScale: String
        let radius: String
        let colorScheme: String
    }

    struct FeaturesDTO: Decodable {
        let enabled: Bool
        let postsEnabled: Bool
        let commentsEnabled: Bool
        let repliesEnabled: Bool
        let imagesEnabled: Bool
        let reactionsEnabled: Bool
        let reactions: [String]
        let viewsEnabled: Bool
        let authorEditEnabled: Bool
        let translationEnabled: Bool
        let profilesEnabled: Bool
        let reportingEnabled: Bool
    }

    struct LimitsDTO: Decodable {
        let postMaxLength: Int
        let commentMaxLength: Int
        let maxImagesPerPost: Int
        let feedPreviewLines: Int
    }

    struct ContextDTO: Decodable {
        let projectName: String
        let projectLogoUrl: String?
    }

    @MainActor
    func toDomain() -> CommunityConfig {
        CommunityConfig(
            theme: CommunityThemeConfig(
                // An unreadable colour falls back to the native theme rather
                // than rendering the accent transparent.
                primary: parseHexColor(theme.primary) ?? CommunityThemeConfig.defaults.primary,
                primaryForeground: parseHexColor(theme.primaryForeground)
                    ?? CommunityThemeConfig.defaults.primaryForeground,
                primaryHex: theme.primary,
                autoGradient: theme.autoGradient ?? true,
                headerTitle: theme.headerTitle,
                headerTitleVisible: theme.headerTitleVisible ?? true,
                fontFamily: CommunityFontFamily(rawValue: theme.fontFamily) ?? .inter,
                fontFamilyName: theme.fontFamilyName,
                fontScale: CommunityFontScale(rawValue: theme.fontScale) ?? .default,
                radius: CommunityRadius(rawValue: theme.radius) ?? .high,
                colorScheme: CommunityColorScheme(rawValue: theme.colorScheme) ?? .system
            ),
            features: CommunityFeatures(
                enabled: features.enabled,
                postsEnabled: features.postsEnabled,
                commentsEnabled: features.commentsEnabled,
                repliesEnabled: features.repliesEnabled,
                imagesEnabled: features.imagesEnabled,
                reactionsEnabled: features.reactionsEnabled,
                // An unknown reaction type (added server-side, binary out of
                // date) is skipped instead of failing the whole decode.
                reactions: features.reactions.compactMap(CommunityReactionKind.init(rawValue:)),
                viewsEnabled: features.viewsEnabled,
                authorEditEnabled: features.authorEditEnabled,
                translationEnabled: features.translationEnabled,
                profilesEnabled: features.profilesEnabled,
                reportingEnabled: features.reportingEnabled
            ),
            limits: CommunityLimits(
                postMaxLength: limits.postMaxLength,
                commentMaxLength: limits.commentMaxLength,
                maxImagesPerPost: limits.maxImagesPerPost,
                feedPreviewLines: limits.feedPreviewLines
            ),
            context: CommunityContext(
                projectName: context.projectName,
                projectLogoUrl: parseURL(context.projectLogoUrl)
            ),
            version: version
        )
    }
}

// MARK: - Author, media

struct CommunityAuthorDTO: Decodable {
    let id: String
    let nickname: String
    let avatarUrl: String?
    let role: String
    let isTeam: Bool

    func toDomain() -> CommunityAuthor {
        CommunityAuthor(
            id: id,
            nickname: nickname,
            avatarUrl: parseURL(avatarUrl),
            role: CommunityMemberRole(rawValue: role) ?? .member,
            isTeam: isTeam
        )
    }
}

struct CommunityMediaDTO: Decodable {
    let url: String
    let width: Int?
    let height: Int?
    let alt: String?

    /// `nil` when the URL is unusable, so the media is simply absent from the
    /// post rather than breaking its rendering.
    func toDomain() -> CommunityMedia? {
        guard let url = parseURL(url) else { return nil }
        return CommunityMedia(url: url, width: width, height: height, alt: alt)
    }
}

// MARK: - Post

struct CommunityPostDTO: Decodable {
    let id: String
    let groupId: String
    let groupName: String
    let author: CommunityAuthorDTO?
    let body: String
    let translatedBody: String?
    let sourceLanguage: String?
    let media: [CommunityMediaDTO]
    let poll: CommunityPollDTO?
    let isPinned: Bool
    let hasAdminTag: Bool
    let likeCount: Int
    let commentCount: Int
    let viewCount: Int
    let myReaction: String?
    let canEdit: Bool
    let canDelete: Bool
    let isPendingReview: Bool
    let publishedAt: String
    let editedAt: String?

    func toDomain() -> CommunityPost {
        CommunityPost(
            id: id,
            groupId: groupId,
            groupName: groupName,
            author: author?.toDomain(),
            body: body,
            translatedBody: translatedBody,
            sourceLanguage: sourceLanguage,
            media: media.compactMap { $0.toDomain() },
            poll: poll?.toDomain(),
            isPinned: isPinned,
            hasAdminTag: hasAdminTag,
            likeCount: likeCount,
            commentCount: commentCount,
            viewCount: viewCount,
            myReaction: myReaction.flatMap(CommunityReactionKind.init(rawValue:)),
            canEdit: canEdit,
            canDelete: canDelete,
            isPendingReview: isPendingReview,
            // An unreadable publication date must not make the post vanish, so
            // it falls back to now and appears at the top.
            publishedAt: CommunityDateParser.parse(publishedAt) ?? Date(),
            editedAt: CommunityDateParser.parse(editedAt)
        )
    }
}

struct CommunityPollDTO: Decodable {
    let options: [CommunityPollOptionDTO]
    let totalVotes: Int
    let myOptionId: String?

    func toDomain() -> CommunityPoll {
        CommunityPoll(
            options: options.map { $0.toDomain() },
            totalVotes: totalVotes,
            myOptionId: myOptionId
        )
    }
}

struct CommunityPollOptionDTO: Decodable {
    let id: String
    let text: String
    let voteCount: Int

    func toDomain() -> CommunityPollOption {
        CommunityPollOption(id: id, text: text, voteCount: voteCount)
    }
}

// MARK: - Comment

struct CommunityCommentDTO: Decodable {
    let id: String
    let postId: String
    let parentCommentId: String?
    let author: CommunityAuthorDTO?
    let body: String
    let translatedBody: String?
    let sourceLanguage: String?
    let likeCount: Int
    let replyCount: Int
    let myReaction: String?
    let canEdit: Bool
    let canDelete: Bool
    let isPendingReview: Bool
    let replies: [CommunityCommentDTO]
    let createdAt: String
    let editedAt: String?

    func toDomain() -> CommunityComment {
        CommunityComment(
            id: id,
            postId: postId,
            parentCommentId: parentCommentId,
            author: author?.toDomain(),
            body: body,
            translatedBody: translatedBody,
            sourceLanguage: sourceLanguage,
            likeCount: likeCount,
            replyCount: replyCount,
            myReaction: myReaction.flatMap(CommunityReactionKind.init(rawValue:)),
            canEdit: canEdit,
            canDelete: canDelete,
            isPendingReview: isPendingReview,
            replies: replies.map { $0.toDomain() },
            createdAt: CommunityDateParser.parse(createdAt) ?? Date(),
            editedAt: CommunityDateParser.parse(editedAt)
        )
    }
}

// MARK: - Profile, group, bootstrap

struct CommunityProfileDTO: Decodable {
    let id: String
    let nickname: String
    let bio: String?
    let avatarUrl: String?
    let role: String
    let isTeam: Bool
    let isAnonymous: Bool
    let postCount: Int
    let commentCount: Int
    let receivedReactionCount: Int
    let joinedAt: String
    let isMe: Bool
    let isBanned: Bool

    func toDomain() -> CommunityProfile {
        CommunityProfile(
            id: id,
            nickname: nickname,
            bio: bio,
            avatarUrl: parseURL(avatarUrl),
            role: CommunityMemberRole(rawValue: role) ?? .member,
            isTeam: isTeam,
            isAnonymous: isAnonymous,
            postCount: postCount,
            commentCount: commentCount,
            receivedReactionCount: receivedReactionCount,
            joinedAt: CommunityDateParser.parse(joinedAt) ?? Date(),
            isMe: isMe,
            isBanned: isBanned
        )
    }
}

struct CommunityGroupDTO: Decodable {
    let id: String
    let name: String
    let description: String?
    let emoji: String?
    let imageUrl: String?
    let isDefault: Bool
    let canPost: Bool
    let postCount: Int

    func toDomain() -> CommunityGroup {
        CommunityGroup(
            id: id,
            name: name,
            description: description,
            emoji: emoji,
            imageUrl: parseURL(imageUrl),
            isDefault: isDefault,
            canPost: canPost,
            postCount: postCount
        )
    }
}

struct CommunityBootstrapDTO: Decodable {
    let config: CommunityConfigDTO
    let groups: [CommunityGroupDTO]
    let profile: CommunityProfileDTO
    let unreadNotificationCount: Int

    @MainActor
    func toDomain() -> CommunityBootstrap {
        CommunityBootstrap(
            config: config.toDomain(),
            groups: groups.map { $0.toDomain() },
            profile: profile.toDomain(),
            unreadNotificationCount: unreadNotificationCount
        )
    }
}

// MARK: - Notification, reaction, translation

struct CommunityNotificationDTO: Decodable {
    let id: String
    let type: String
    let actor: ActorDTO?
    let targetType: String
    let targetId: String
    let postId: String?
    let excerpt: String?
    let isRead: Bool
    let createdAt: String

    struct ActorDTO: Decodable {
        let id: String
        let nickname: String
        let avatarUrl: String?
    }

    /// `nil` when this binary does not know the type: better to hide a
    /// notification than to show one we cannot route on tap.
    func toDomain() -> CommunityNotification? {
        guard let type = CommunityNotificationType(rawValue: type) else { return nil }
        return CommunityNotification(
            id: id,
            type: type,
            actor: actor.map {
                CommunityNotificationActor(
                    id: $0.id,
                    nickname: $0.nickname,
                    avatarUrl: parseURL($0.avatarUrl)
                )
            },
            targetType: targetType,
            targetId: targetId,
            postId: postId,
            excerpt: excerpt,
            isRead: isRead,
            createdAt: CommunityDateParser.parse(createdAt) ?? Date()
        )
    }
}

/// Result of a reaction toggle, enough to refresh the counter without
/// refetching the page.
struct CommunityReactionResultDTO: Decodable {
    let targetId: String
    let myReaction: String?
    let likeCount: Int
}

struct CommunityTranslationDTO: Decodable {
    let targetType: String
    let targetId: String
    let translatedBody: String
    let sourceLanguage: String?
    let targetLanguage: String
}

// MARK: - Request bodies

struct CreatePostBody: Encodable {
    let groupId: String?
    let body: String
    let media: [MediaInput]
    let poll: PollInput?

    struct MediaInput: Encodable {
        let url: String
        let width: Int?
        let height: Int?
        let alt: String?
    }

    struct PollInput: Encodable {
        let options: [String]
    }
}

struct CommunityPollVoteBody: Encodable {
    let optionId: String
}

struct CommunityPollVoteResultDTO: Decodable {
    let postId: String
    let poll: CommunityPollDTO
}

struct UpdatePostBody: Encodable {
    let body: String
}

struct CreateCommentBody: Encodable {
    let body: String
    let parentCommentId: String?
}

struct ToggleReactionBody: Encodable {
    let kind: String
}

struct TrackViewsBody: Encodable {
    let postIds: [String]
}

struct ReportBody: Encodable {
    let targetType: String
    let targetId: String
    let reason: String
    let note: String?
}

struct SetUserBody: Encodable {
    let nickname: String?
    let avatarUrl: String?
    let bio: String?
}

struct UpdateProfileBody: Encodable {
    let nickname: String?
    let bio: String?
    let avatarUrl: String?
    let isAnonymous: Bool?
}

struct MarkNotificationsReadBody: Encodable {
    let notificationIds: [String]
}

struct TranslateBody: Encodable {
    let targetType: String
    let targetId: String
    let targetLanguage: String?
}
