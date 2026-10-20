import SwiftUI
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

/// What `communityView`, `communityViewController` or `presentCommunity` was
/// given: a `nil` handler leaves that field to the SDK.
struct ProfileEditingHandlers {
    var onEditProfile: (@MainActor () -> Void)?
    var onEditProfilePhoto: (@MainActor () -> Void)?
    var onEditProfileName: (@MainActor () -> Void)?
}

/// The profile editing handlers of the community UI on screen.
///
/// Handlers live as long as the view or presentation that declared them. What
/// the app owns outlives it: a post opened from a notification, with no feed
/// mounted, must not let the member edit a field the app declared as its own,
/// so such an entry is hidden rather than handed back to the SDK.
@MainActor
enum CommunityProfileEditing {
    private struct Registration {
        let token: UUID
        let handlers: ProfileEditingHandlers
        weak var host: UIViewController?
        let isPresented: Bool
    }

    /// In mount order: closing a presented feed hands the handlers back to the
    /// feed embedded under it.
    private static var registrations: [Registration] = []
    private static var current: Registration? { registrations.last }
    private(set) static var ownsProfile = false
    private(set) static var ownsPhoto = false
    private(set) static var ownsName = false

    static func register(
        _ handlers: ProfileEditingHandlers,
        token: UUID,
        host: UIViewController?,
        isPresented: Bool
    ) {
        registrations.removeAll { $0.token == token }
        registrations.append(
            Registration(token: token, handlers: handlers, host: host, isPresented: isPresented)
        )
        ownsProfile = handlers.onEditProfile != nil
        ownsPhoto = handlers.onEditProfilePhoto != nil
        ownsName = handlers.onEditProfileName != nil
    }

    static func unregister(token: UUID) {
        registrations.removeAll { $0.token == token }
    }

    static var profileHandler: (@MainActor () -> Void)? { current?.handlers.onEditProfile }
    static var photoHandler: (@MainActor () -> Void)? { current?.handlers.onEditProfilePhoto }
    static var nameHandler: (@MainActor () -> Void)? { current?.handlers.onEditProfileName }

    static var canOpenEditor: Bool { !ownsProfile || profileHandler != nil }

    static func begin(orOpenSdkEditor openSdkEditor: () -> Void) {
        if let handler = profileHandler {
            handOver(to: handler)
        } else if !ownsProfile {
            openSdkEditor()
        }
    }

    /// Closes the SDK's sheets, then calls the host. In a Flutter or React
    /// Native app the host's screen is drawn under every native sheet: called
    /// first, it would open out of sight.
    static func handOver(to handler: @escaping @MainActor () -> Void) {
        let host = current?.host
        // An embedded feed's sheets can be presented by its controller or by an
        // ancestor (Flutter's view controller); a presented feed goes entirely.
        let holder = current?.isPresented == true
            ? host?.presentingViewController
            : host.flatMap { start in
                sequence(first: start, next: \.parent).first { $0.presentedViewController != nil }
            }
        guard let holder else {
            handler()
            return
        }
        holder.dismiss(animated: true) { handler() }
    }
}

/// Reports the controller hosting the SwiftUI tree it is placed in.
struct CommunityHostControllerReader: UIViewControllerRepresentable {
    let onResolve: (UIViewController) -> Void

    func makeUIViewController(context: Context) -> Reader {
        Reader(onResolve: onResolve)
    }

    func updateUIViewController(_ controller: Reader, context: Context) {}

    final class Reader: UIViewController {
        let onResolve: (UIViewController) -> Void

        init(onResolve: @escaping (UIViewController) -> Void) {
            self.onResolve = onResolve
            super.init(nibName: nil, bundle: nil)
        }

        required init?(coder: NSCoder) { nil }

        override func didMove(toParent parent: UIViewController?) {
            super.didMove(toParent: parent)
            if let parent { onResolve(parent) }
        }
    }
}
