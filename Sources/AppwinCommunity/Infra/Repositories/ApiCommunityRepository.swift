import Foundation
import AppwinCore

/// HTTP implementation of `CommunityRepository`.
///
/// The scope (org, project, member profile) is resolved server-side by
/// `CommunitySdkGuard` from the bearer: no tenant identifier travels in the
/// paths. The SDK only ever knows content ids.
///
/// The reader's language goes out in `X-Appwin-Language` on the routes that can
/// translate; the server uses it to pick the target language.
final class ApiCommunityRepository: CommunityRepository {
    let clientApi: ClientApi
    let base = "/api/sdk/community/v1"

    init(clientApi: ClientApi) {
        self.clientApi = clientApi
    }

    /// Device language, reduced to its ISO 639-1 code.
    ///
    /// The region is dropped (`fr-CA` becomes `fr`): translating into Canadian
    /// French and French French yields the same text, and would split the
    /// server cache in two for nothing.
    private var languageHeader: [String: String] {
        guard let code = Locale.preferredLanguages.first?.split(separator: "-").first else {
            return [:]
        }
        return ["X-Appwin-Language": String(code).lowercased()]
    }

    // MARK: - Startup

    func bootstrap() async throws -> CommunityBootstrap {
        let dto: CommunityBootstrapDTO = try await clientApi.request(
            path: "\(base)/bootstrap",
            httpMethod: .get
        )
        return await MainActor.run { dto.toDomain() }
    }

    func fetchConfig(cachedVersion: Int?) async throws -> CommunityConfigFetchResult? {
        var extraHeaders: [String: String] = [:]
        if let cachedVersion, cachedVersion > 0 {
            extraHeaders["If-None-Match"] = String(cachedVersion)
        }
        let (status, data) = try await clientApi.requestRaw(
            path: "\(base)/config",
            httpMethod: .get,
            extraHeaders: extraHeaders
        )
        if status == 304 { return nil }   // cache local toujours valide
        let dto = try JSONDecoder().decode(CommunityConfigDTO.self, from: data)
        let config = await MainActor.run { dto.toDomain() }
        return CommunityConfigFetchResult(config: config, raw: data)
    }

    // MARK: - Fil

    func feed(
        groupId: String?,
        authorProfileId: String?,
        sort: CommunityFeedSort,
        cursor: String?,
        limit: Int
    ) async throws -> CursorPaginated<CommunityPost> {
        var items = [
            URLQueryItem(name: "limit", value: String(limit)),
            URLQueryItem(name: "sort", value: sort.rawValue),
        ]
        if let cursor { items.append(URLQueryItem(name: "cursor", value: cursor)) }
        if let groupId { items.append(URLQueryItem(name: "groupId", value: groupId)) }
        if let authorProfileId {
            items.append(URLQueryItem(name: "authorProfileId", value: authorProfileId))
        }

        var components = URLComponents()
        components.queryItems = items
        let query = components.percentEncodedQuery.map { "?\($0)" } ?? ""

        let page: CursorPage<CommunityPostDTO> = try await clientApi.request(
            path: "\(base)/feed\(query)",
            httpMethod: .get,
            extraHeaders: languageHeader
        )
        return CursorPaginated(
            items: page.data.map { $0.toDomain() },
            nextCursor: page.nextCursor
        )
    }

    func createPost(
        groupId: String?,
        body: String,
        media: [CommunityMedia],
        pollOptions: [String]?
    ) async throws -> CommunityPost {
        let dto: CommunityPostDTO = try await clientApi.request(
            path: "\(base)/posts",
            httpMethod: .post,
            body: CreatePostBody(
                groupId: groupId,
                body: body,
                media: media.map {
                    CreatePostBody.MediaInput(
                        url: $0.url.absoluteString,
                        width: $0.width,
                        height: $0.height,
                        alt: $0.alt
                    )
                },
                poll: pollOptions.map { CreatePostBody.PollInput(options: $0) }
            )
        )
        return dto.toDomain()
    }

    func voteOnPoll(postId: String, optionId: String) async throws -> CommunityPoll {
        let dto: CommunityPollVoteResultDTO = try await clientApi.request(
            path: "\(base)/posts/\(postId)/poll/votes",
            httpMethod: .post,
            body: CommunityPollVoteBody(optionId: optionId)
        )
        return dto.poll.toDomain()
    }

    func updatePost(postId: String, body: String) async throws -> CommunityPost {
        let dto: CommunityPostDTO = try await clientApi.request(
            path: "\(base)/posts/\(postId)",
            httpMethod: .patch,
            body: UpdatePostBody(body: body)
        )
        return dto.toDomain()
    }

    func deletePost(postId: String) async throws {
        try await clientApi.requestVoid(path: "\(base)/posts/\(postId)", httpMethod: .delete)
    }

    // MARK: - Commentaires

    func comments(postId: String, limit: Int, offset: Int) async throws -> [CommunityComment] {
        let dtos: [CommunityCommentDTO] = try await clientApi.request(
            path: "\(base)/posts/\(postId)/comments?limit=\(limit)&offset=\(offset)",
            httpMethod: .get,
            extraHeaders: languageHeader
        )
        return dtos.map { $0.toDomain() }
    }

    func createComment(
        postId: String,
        body: String,
        parentCommentId: String?
    ) async throws -> CommunityComment {
        let dto: CommunityCommentDTO = try await clientApi.request(
            path: "\(base)/posts/\(postId)/comments",
            httpMethod: .post,
            body: CreateCommentBody(body: body, parentCommentId: parentCommentId)
        )
        return dto.toDomain()
    }

    func deleteComment(commentId: String) async throws {
        try await clientApi.requestVoid(
            path: "\(base)/comments/\(commentId)",
            httpMethod: .delete
        )
    }

    // MARK: - Reactions, views

    func reactToPost(
        postId: String,
        kind: CommunityReactionKind
    ) async throws -> CommunityReactionResultDTO {
        try await clientApi.request(
            path: "\(base)/posts/\(postId)/reactions",
            httpMethod: .post,
            body: ToggleReactionBody(kind: kind.rawValue)
        )
    }

    func reactToComment(
        commentId: String,
        kind: CommunityReactionKind
    ) async throws -> CommunityReactionResultDTO {
        try await clientApi.request(
            path: "\(base)/comments/\(commentId)/reactions",
            httpMethod: .post,
            body: ToggleReactionBody(kind: kind.rawValue)
        )
    }

    func trackViews(postIds: [String]) async throws {
        guard !postIds.isEmpty else { return }
        try await clientApi.requestVoid(
            path: "\(base)/views",
            httpMethod: .post,
            body: TrackViewsBody(postIds: postIds)
        )
    }

    // MARK: - Profil

    func profile(profileId: String) async throws -> CommunityProfile {
        let dto: CommunityProfileDTO = try await clientApi.request(
            path: "\(base)/profiles/\(profileId)",
            httpMethod: .get
        )
        return dto.toDomain()
    }

    func setUser(
        nickname: String?,
        avatarUrl: String?,
        bio: String?
    ) async throws -> CommunityProfile {
        let dto: CommunityProfileDTO = try await clientApi.request(
            path: "\(base)/me",
            httpMethod: .post,
            body: SetUserBody(nickname: nickname, avatarUrl: avatarUrl, bio: bio)
        )
        return dto.toDomain()
    }

    func updateOwnProfile(
        nickname: String?,
        bio: String?,
        avatarUrl: String?,
        isAnonymous: Bool?
    ) async throws -> CommunityProfile {
        let dto: CommunityProfileDTO = try await clientApi.request(
            path: "\(base)/me",
            httpMethod: .patch,
            body: UpdateProfileBody(
                nickname: nickname,
                bio: bio,
                avatarUrl: avatarUrl,
                isAnonymous: isAnonymous
            )
        )
        return dto.toDomain()
    }

    // MARK: - Signalement, notifications, traduction

    func report(
        targetType: String,
        targetId: String,
        reason: CommunityReportReason,
        note: String?
    ) async throws {
        try await clientApi.requestVoid(
            path: "\(base)/reports",
            httpMethod: .post,
            body: ReportBody(
                targetType: targetType,
                targetId: targetId,
                reason: reason.rawValue,
                note: note
            )
        )
    }

    func notifications(limit: Int, offset: Int) async throws -> [CommunityNotification] {
        let dtos: [CommunityNotificationDTO] = try await clientApi.request(
            path: "\(base)/notifications?limit=\(limit)&offset=\(offset)",
            httpMethod: .get
        )
        return dtos.compactMap { $0.toDomain() }
    }

    func markNotificationsRead(ids: [String]) async throws {
        try await clientApi.requestVoid(
            path: "\(base)/notifications/read",
            httpMethod: .post,
            body: MarkNotificationsReadBody(notificationIds: ids)
        )
    }

    func translate(targetType: String, targetId: String) async throws -> CommunityTranslationDTO {
        try await clientApi.request(
            path: "\(base)/translate",
            httpMethod: .post,
            body: TranslateBody(
                targetType: targetType,
                targetId: targetId,
                // Absent: the server falls back to `X-Appwin-Language`.
                targetLanguage: nil
            ),
            extraHeaders: languageHeader
        )
    }
}
