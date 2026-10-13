import Foundation

/// What moderators and admins do from the app, and the sanctions a member is
/// told about. Separate from `CommunityRepository`: most members never touch it.
protocol CommunityModerationRepository: Sendable {
    func queue(offset: Int, limit: Int) async throws -> ModerationQueuePage

    func decide(
        targetType: ModerationTargetType,
        targetId: String,
        action: ModerationAction,
        reason: String?,
        durationHours: Int?,
        reportIds: [String]
    ) async throws

    func moveToGroup(postId: String, groupId: String) async throws
    func pin(postId: String, settings: PinSettings) async throws
    func unpin(postId: String) async throws

    /// Removed content, warnings, bans: the cards behind the bell.
    func sanctions() async throws -> [CommunityNotification]
    /// « J'ai compris ».
    func acknowledge(notificationIds: [String]) async throws
}
