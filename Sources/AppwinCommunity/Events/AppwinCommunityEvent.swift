import Foundation

/// Something the current member just did in Community, once the server has
/// accepted it. Never emitted optimistically, and never for other members'
/// activity.
public enum AppwinCommunityEvent: Sendable, Equatable {
    /// The member published a post.
    case postCreated(postId: String)
    /// The member commented on a post.
    case commentCreated(commentId: String, postId: String)
    /// The member replied to a comment. `commentId` is the comment replied to.
    case replyCreated(replyId: String, commentId: String, postId: String)
    /// The member set, changed or removed a reaction. `commentId` is set when
    /// the reaction is on a comment; `reaction` is the reaction key as the API
    /// names it (`like`, `love`...), `nil` when the reaction was removed.
    case reactionModified(postId: String, commentId: String?, reaction: String?)
    /// The member's profile changed, from the SDK's editor or from `setUser`.
    case profileUpdated(profileId: String)
}

/// Multicasts events to every `AppwinCommunity.events` consumer.
@MainActor
enum AppwinCommunityEvents {
    private static var subscribers: [UUID: AsyncStream<AppwinCommunityEvent>.Continuation] = [:]

    static func stream() -> AsyncStream<AppwinCommunityEvent> {
        // Bounded like Android's SharedFlow (64, drop oldest): a consumer that
        // stopped reading must not grow memory forever.
        let (stream, continuation) = AsyncStream.makeStream(
            of: AppwinCommunityEvent.self,
            bufferingPolicy: .bufferingNewest(64)
        )
        let id = UUID()
        subscribers[id] = continuation
        continuation.onTermination = { _ in
            Task { @MainActor in subscribers[id] = nil }
        }
        return stream
    }

    static func emit(_ event: AppwinCommunityEvent) {
        subscribers.values.forEach { $0.yield(event) }
    }
}
