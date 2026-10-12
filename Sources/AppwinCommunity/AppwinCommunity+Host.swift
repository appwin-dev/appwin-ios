import Foundation
import AppwinCore

/// A post to open, from a notification tap or `AppwinCommunity.openPost`.
public struct AppwinCommunityPostTarget: Sendable, Equatable {
    public let postId: String
    /// Root comment whose reply thread opens over the post, when set.
    public let commentId: String?

    public init(postId: String, commentId: String? = nil) {
        self.postId = postId
        self.commentId = commentId
    }
}

extension AppwinCommunity {
    // MARK: - Host hooks

    /// Takes over navigation when the member taps a Community notification.
    ///
    /// Unset, the SDK opens the post itself: in the feed when it is on screen,
    /// otherwise in a sheet over the app. Set it when Community lives in a tab,
    /// to switch to that tab first, then call `openPost(_:commentId:)`:
    ///
    /// ```swift
    /// AppwinCommunity.onNotificationTap = { target in
    ///   selectedTab = .community
    ///   AppwinCommunity.openPost(target.postId, commentId: target.commentId)
    /// }
    /// ```
    ///
    /// Set it before `initialize()`, so a tap that launched the app reaches it.
    public static var onNotificationTap: (@MainActor (AppwinCommunityPostTarget) -> Void)?

    /// Replaces the SDK's profile editor with your own.
    ///
    /// When set, every SDK entry point that edits the nickname, photo or bio
    /// calls it instead of opening the SDK's editor. Push the result with
    /// `setUser(nickname:avatarUrl:bio:)`, which refreshes the mounted screens.
    public static var onEditProfile: (@MainActor () -> Void)?

    /// Opens a post, and optionally the reply thread under one of its comments.
    ///
    /// Opens in the feed when one is mounted, or mounts within a moment of the
    /// call: switching to the Community tab right before calling this is
    /// enough, even if that tab was never shown. Otherwise presents the post
    /// in a sheet over the app. Does nothing, and logs why, while Community is
    /// not ready.
    public static func openPost(_ postId: String, commentId: String? = nil) {
        guard isReady else {
            reportNotReady()
            return
        }
        CommunityFeedPresence.deliver(
            CommunityPushTarget(postId: postId, threadCommentId: commentId),
            fallback: CommunityPostModalView.present
        )
    }

    static func routeNotificationTap(_ target: CommunityPushTarget) {
        guard isReady else {
            reportNotReady()
            return
        }
        if let onNotificationTap {
            onNotificationTap(
                AppwinCommunityPostTarget(postId: target.postId, commentId: target.threadCommentId)
            )
        } else if let feed = CommunityFeedPresence.visible {
            feed.targets.send(target)
        } else {
            CommunityPostModalView.present(target)
        }
    }

    // MARK: - Streams

    /// The current member's own actions (posts, comments, replies, reactions,
    /// profile changes), each emitted once the server has accepted it.
    ///
    /// Every access returns an independent stream; it ends when the consuming
    /// task is cancelled. Events that happen while nobody consumes are not
    /// replayed.
    ///
    /// ```swift
    /// for await event in AppwinCommunity.events {
    ///   if case .postCreated = event { rewards.grant(.firstPost) }
    /// }
    /// ```
    public static var events: AsyncStream<AppwinCommunityEvent> {
        AppwinCommunityEvents.stream()
    }

    /// The unread notification count, for a live badge.
    ///
    /// Emits the known count on subscribe, refreshes it from the server, then
    /// emits each change (never the same value twice in a row). Kept current by
    /// Community pushes and by the app returning to the foreground, while at
    /// least one stream is being consumed. Every access returns an independent
    /// stream; it ends when the consuming task is cancelled.
    public static var unreadNotificationCountUpdates: AsyncStream<Int> {
        UnreadCountStore.stream()
    }
}

/// Where the SDK's profile editor would open.
@MainActor
enum CommunityProfileEditing {
    /// Hands over to the host's editor when it registered one.
    static func begin(orOpenSdkEditor openSdkEditor: () -> Void) {
        if let hostEditor = AppwinCommunity.onEditProfile {
            hostEditor()
        } else {
            openSdkEditor()
        }
    }
}
