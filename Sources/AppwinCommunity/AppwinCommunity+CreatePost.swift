import Foundation
@_spi(Appwin) import AppwinCore

extension AppwinCommunity {
    /// The most photos one post carries, the server's own limit.
    static let createPostMaxImages = 10

    /// Publishes a post as the current member, from the host app's own screen
    /// (an end-of-workout "share" card, say), without opening the feed.
    ///
    /// ```swift
    /// let post = try await AppwinCommunity.createPost(
    ///     text: "Super séance ce matin !",
    ///     images: [jpegData]
    /// )
    /// if post.status == .pendingReview { showHeldByModerationNote() }
    /// ```
    ///
    /// - Parameters:
    ///   - text: The post's text. Required: a post without text is refused.
    ///   - images: Up to 10 encoded images (JPEG, PNG, HEIC...), in display
    ///     order. Each is downsized to 1600 px and re-encoded before upload.
    ///   - groupId: The group to post in, as shown in the dashboard. `nil`
    ///     posts in the project's default group.
    /// - Returns: The created post. It goes through the same moderation as a
    ///   post written in the feed, so read its `status`.
    /// - Throws: `AppwinCommunityError.invalidArgument` for empty text, too many
    ///   images or an image that cannot be decoded, before any request;
    ///   `AppwinApiError` when the server refuses (`.http(403)`: Community paused
    ///   or disabled, member banned or muted, group closed to members;
    ///   `.http(429)`: posting too fast; `.http(400)`: text too long, unknown group)
    ///   or the network fails.
    ///
    /// Call `AppwinCommunity.setUser(...)` first if the member should appear
    /// under their name rather than anonymously.
    public static func createPost(
        text: String,
        images: [Data] = [],
        groupId: String? = nil
    ) async throws -> CommunityCreatedPost {
        let body = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !body.isEmpty else {
            throw AppwinCommunityError.invalidArgument("createPost: text is empty")
        }
        guard images.count <= createPostMaxImages else {
            throw AppwinCommunityError.invalidArgument(
                "createPost: \(images.count) images, at most \(createPostMaxImages)"
            )
        }
        let repo = Factory.repository()
        let media = try await uploadInOrder(images, repo: repo)
        let post = try await repo.createPost(
            groupId: groupId,
            body: body,
            media: media,
            pollOptions: nil
        )
        // A mounted feed would only show the post on its next pull to refresh.
        NotificationCenter.default.post(name: .appwinCommunityUiRefresh, object: nil)
        return CommunityCreatedPost(post)
    }

    /// Uploads in parallel, returns in the caller's order.
    private static func uploadInOrder(
        _ images: [Data],
        repo: CommunityRepository
    ) async throws -> [CommunityMedia] {
        guard !images.isEmpty else { return [] }
        return try await withThrowingTaskGroup(of: (Int, CommunityMedia).self) { group in
            for (index, data) in images.enumerated() {
                group.addTask {
                    do {
                        return (index, try await repo.uploadImage(data, filenamePrefix: "post"))
                    } catch is ImageCompressionError {
                        throw AppwinCommunityError.invalidArgument(
                            "createPost: image \(index) could not be decoded"
                        )
                    }
                }
            }
            var media = [CommunityMedia?](repeating: nil, count: images.count)
            for try await (index, item) in group { media[index] = item }
            return media.compactMap { $0 }
        }
    }
}

/// A post created by `AppwinCommunity.createPost`.
public struct CommunityCreatedPost: Sendable, Equatable {
    /// Where moderation put the post.
    public enum Status: String, Sendable {
        /// Online: the community sees it.
        case published
        /// Held for review (or the member is shadow banned): only its author
        /// sees it, until a moderator publishes it.
        case pendingReview
        /// Refused by moderation as it was written. Its author is told why in
        /// the feed's notifications.
        case removed
    }

    /// The post's id, for `AppwinCommunity.openPost(_:)`.
    public let id: String
    public let status: Status

    init(_ post: CommunityPost) {
        self.id = post.id
        self.status = post.isRemoved ? .removed : post.isPendingReview ? .pendingReview : .published
    }

    /// Shape carried over the Flutter and React Native bridges.
    public var asDictionary: [String: Any] {
        ["id": id, "status": status.rawValue]
    }
}
