import Foundation
import AppwinCore

/// Composition root du SDK Community.
///
/// The repository is created on demand rather than retained: `ClientApi` is
/// stateless (its headers are resolved by closure per request), so caching it
/// would save nothing and would become a trap if the host app called
/// `AppwinCore.configure` again with a different `baseUrl`.
@MainActor
enum Factory {
    static func repository() -> CommunityRepository {
        guard let client = AppwinCore.client else {
            // `configure` was not called: rather than crashing on use, return a
            // repository that fails cleanly on every call, so the UI shows its
            // error state.
            return UnconfiguredCommunityRepository()
        }
        return ApiCommunityRepository(clientApi: client)
    }

    static func makeSession() -> CommunitySession {
        CommunitySession(repo: repository(), appId: AppwinCore.projectAppId ?? "")
    }

    static func makeFeedStore() -> FeedStore {
        FeedStore(repo: repository())
    }
}

/// Fallback repository for when `AppwinCore.configure(projectAppId:)` was never
/// called. Every method throws: the screen shows its error instead of crashing
/// the host app, which makes a missed integration legible in development.
private struct UnconfiguredCommunityRepository: CommunityRepository {
    private var error: Error { AppwinCommunityError.notInitialized }

    func bootstrap() async throws -> CommunityBootstrap { throw error }
    func fetchConfig(cachedVersion: Int?) async throws -> CommunityConfigFetchResult? { throw error }
    func feed(
        groupId: String?,
        sort: CommunityFeedSort,
        cursor: String?,
        limit: Int
    ) async throws -> CursorPaginated<CommunityPost> { throw error }
    func createPost(groupId: String?, body: String, media: [CommunityMedia]) async throws -> CommunityPost { throw error }
    func updatePost(postId: String, body: String) async throws -> CommunityPost { throw error }
    func deletePost(postId: String) async throws { throw error }
    func comments(postId: String, limit: Int, offset: Int) async throws -> [CommunityComment] { throw error }
    func createComment(postId: String, body: String, parentCommentId: String?) async throws -> CommunityComment { throw error }
    func deleteComment(commentId: String) async throws { throw error }
    func reactToPost(postId: String, kind: CommunityReactionKind) async throws -> CommunityReactionResultDTO { throw error }
    func reactToComment(commentId: String, kind: CommunityReactionKind) async throws -> CommunityReactionResultDTO { throw error }
    func trackViews(postIds: [String]) async throws { throw error }
    func profile(profileId: String) async throws -> CommunityProfile { throw error }
    func setUser(nickname: String?, avatarUrl: String?, bio: String?) async throws -> CommunityProfile { throw error }
    func updateOwnProfile(
        nickname: String?,
        bio: String?,
        avatarUrl: String?,
        isAnonymous: Bool?
    ) async throws -> CommunityProfile { throw error }
    func report(
        targetType: String,
        targetId: String,
        reason: CommunityReportReason,
        note: String?
    ) async throws { throw error }
    func notifications(limit: Int, offset: Int) async throws -> [CommunityNotification] { throw error }
    func markNotificationsRead(ids: [String]) async throws { throw error }
    func translate(targetType: String, targetId: String) async throws -> CommunityTranslationDTO { throw error }
}

/// Erreurs propres au SDK Community.
public enum AppwinCommunityError: LocalizedError {
    /// `AppwinCore.configure(projectAppId:)` was not called.
    case notInitialized
    case invalidArgument(String)

    public var errorDescription: String? {
        switch self {
        case .notInitialized:
            return "AppwinCommunity: call AppwinCore.configure(projectAppId:) before using the SDK."
        case .invalidArgument(let detail):
            return "AppwinCommunity: invalid argument - \(detail)"
        }
    }
}
