import Foundation
import AppwinCore

/// HTTP implementation of `CommunityModerationRepository`. The API refuses the
/// moderation routes to plain members; the UI only offers them to moderators.
final class ApiCommunityModerationRepository: CommunityModerationRepository {
    let clientApi: ClientApi
    private let base = "/api/sdk/community/v1"

    init(clientApi: ClientApi) {
        self.clientApi = clientApi
    }

    func queue(offset: Int, limit: Int) async throws -> ModerationQueuePage {
        let dto: ModerationQueueDTO = try await clientApi.request(
            path: "\(base)/moderation/queue?limit=\(limit)&offset=\(offset)",
            httpMethod: .get
        )
        return dto.toDomain()
    }

    func decide(
        targetType: ModerationTargetType,
        targetId: String,
        action: ModerationAction,
        reason: String?,
        durationHours: Int?,
        reportIds: [String]
    ) async throws {
        try await clientApi.requestVoid(
            path: "\(base)/moderation/decisions",
            httpMethod: .post,
            body: ModerationDecisionBody(
                targetType: targetType.rawValue,
                targetId: targetId,
                action: action.rawValue,
                reason: reason,
                durationHours: durationHours,
                reportIds: reportIds
            )
        )
    }

    func moveToGroup(postId: String, groupId: String) async throws {
        try await moderatePost(postId: postId, body: ModeratePostBody(groupId: groupId))
    }

    func pin(postId: String, settings: PinSettings) async throws {
        try await moderatePost(postId: postId, body: ModeratePostBody(isPinned: true, pin: settings))
    }

    func unpin(postId: String) async throws {
        try await moderatePost(postId: postId, body: ModeratePostBody(isPinned: false))
    }

    func sanctions() async throws -> [CommunityNotification] {
        let dtos: [CommunityNotificationDTO] = try await clientApi.request(
            path: "\(base)/notifications?kind=sanctions&limit=50",
            httpMethod: .get
        )
        return dtos.compactMap { $0.toDomain() }
    }

    func acknowledge(notificationIds: [String]) async throws {
        try await clientApi.requestVoid(
            path: "\(base)/notifications/read",
            httpMethod: .post,
            body: MarkNotificationsReadBody(notificationIds: notificationIds)
        )
    }

    private func moderatePost(postId: String, body: ModeratePostBody) async throws {
        try await clientApi.requestVoid(
            path: "\(base)/moderation/posts/\(postId)",
            httpMethod: .patch,
            body: body
        )
    }
}
