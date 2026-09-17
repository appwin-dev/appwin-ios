// Domain layer contracts. The Infra implementation speaks HTTP; the stores know
// only these protocols, which makes them testable with a double.

import Foundation
import AppwinCore

/// One config fetch's result: the parsed config plus the raw body, for the local
/// cache, which replays the same decode on the next launch.
struct CommunityConfigFetchResult {
    let config: CommunityConfig
    let raw: Data
}

/// Feed sort. `recent` is the default: strictly reverse-chronological, readable
/// and predictable. `top` ranks by engagement.
enum CommunityFeedSort: String, Sendable {
    case recent, top
}

protocol CommunityRepository: Sendable {
    /// Config, groupes, profil et pastille en un aller-retour.
    func bootstrap() async throws -> CommunityBootstrap

    /// Config alone, with `If-None-Match`: `nil` on a `304`.
    func fetchConfig(cachedVersion: Int?) async throws -> CommunityConfigFetchResult?

    // MARK: Fil

    func feed(
        groupId: String?,
        authorProfileId: String?,
        sort: CommunityFeedSort,
        cursor: String?,
        limit: Int
    ) async throws -> CursorPaginated<CommunityPost>

    func createPost(
        groupId: String?,
        body: String,
        media: [CommunityMedia],
        pollOptions: [String]?
    ) async throws -> CommunityPost

    func updatePost(postId: String, body: String) async throws -> CommunityPost
    func deletePost(postId: String) async throws
    func voteOnPoll(postId: String, optionId: String) async throws -> CommunityPoll

    // MARK: Commentaires

    func comments(postId: String, limit: Int, offset: Int) async throws -> [CommunityComment]
    func createComment(postId: String, body: String, parentCommentId: String?) async throws -> CommunityComment
    func deleteComment(commentId: String) async throws

    // MARK: Reactions, views

    func reactToPost(postId: String, kind: CommunityReactionKind) async throws -> CommunityReactionResultDTO
    func reactToComment(commentId: String, kind: CommunityReactionKind) async throws -> CommunityReactionResultDTO
    func trackViews(postIds: [String]) async throws

    // MARK: Profil

    func profile(profileId: String) async throws -> CommunityProfile
    func setUser(nickname: String?, avatarUrl: String?, bio: String?) async throws -> CommunityProfile
    func updateOwnProfile(
        nickname: String?,
        bio: String?,
        avatarUrl: String?,
        isAnonymous: Bool?
    ) async throws -> CommunityProfile

    /// Uploads an image via community sign/confirm and returns a public URL.
    func uploadMedia(
        data: Data,
        mimeType: String,
        filename: String,
        width: Int?,
        height: Int?
    ) async throws -> CommunityUploadedMedia

    // MARK: Signalement, notifications, traduction

    func report(
        targetType: String,
        targetId: String,
        reason: CommunityReportReason,
        note: String?
    ) async throws

    func notifications(limit: Int, offset: Int) async throws -> [CommunityNotification]
    func markNotificationsRead(ids: [String]) async throws
    func translate(targetType: String, targetId: String) async throws -> CommunityTranslationDTO
}
