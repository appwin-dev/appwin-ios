// AppwinCommunity - native iOS SDK for the Community product (ADR-0019).
//
// Intercom/Octopus model: the whole UI lives here, natively. The host app
// provides an entry point (a tab, a button) and the SDK renders the feed.
//
// Depends on AppwinCore plus Foundation / UIKit / SwiftUI only (ADR-0019 §109).

import Foundation
import SwiftUI
import UIKit
import AppwinCore

@MainActor
public enum AppwinCommunity {
    /// Also a sanity check for the Dart-to-Swift bridge.
    public static let version = "0.1.0-dev"

    // MARK: - Lifecycle

    /// Prepares Community for this app, and says whether it may be used.
    ///
    /// Call it after `AppwinCore.configure(projectAppId:)` and **before**
    /// mounting the feed, then gate your own UI on the result: the SDK cannot
    /// remove your tab, it does not own your navigation.
    ///
    /// ```swift
    /// if await AppwinCommunity.initialize().isReady {
    ///     tabs.append(.community)
    /// }
    /// ```
    ///
    /// Idempotent, and cheap after the first call: the three products share one
    /// server round trip and its cached verdict.
    ///
    /// Set `onNotificationTap` before calling it: a notification tap that
    /// launched the app is replayed right after it returns `.ready`.
    @discardableResult
    public static func initialize() async -> AppwinInitResult {
        // So cold-start push taps are captured even if the host forgot to call
        // `AppwinNotifications.ensurePushNotificationDelegate()` early.
        AppwinCore.preparePushCapture()
        // A mounted feed was bootstrapped for the previous customer: its header
        // avatar and posting rights would stay on them until the next launch.
        AppwinCore.observeIdentity(.community) { change in
            guard change == .session else { return }
            NotificationCenter.default.post(name: .appwinCommunityUiRefresh, object: nil)
        }
        let result = await AppwinCore.availability(of: .community)
        CommunityAvailability.shared.apply(result)
        CommunityAvailability.shared.follow()
        if !result.isReady { AppwinCore.reportUnavailable(.community, result) }
        else { AppwinCore.reportMissingPushToken(for: .community) }
        return result
    }

    /// The latest verdict: the result of `initialize()`, then kept current as
    /// the server's answer changes (a plan that lapses, a dashboard toggle).
    /// `nil` until `initialize()` has returned.
    public static var lastResult: AppwinInitResult? { CommunityAvailability.shared.result }

    /// Whether `lastResult` is `.ready`. Rendering is gated on it.
    public static var isReady: Bool { lastResult?.isReady ?? false }

    /// Logs why Community is closed, with the real reason.
    static func reportNotReady() {
        if let lastResult {
            AppwinCore.reportUnavailable(.community, lastResult)
            return
        }
        let message = "[Appwin] community is not available: AppwinCommunity.initialize() "
            + "has not been called. Call it after AppwinCore.configure(projectAppId:)."
        #if DEBUG
        print(message)
        #else
        NSLog("%@", message)
        #endif
    }

    // MARK: - Identity

    /// Pushes the identity the host app already knows, so the member does not
    /// type it twice. Every field is optional and an omitted one is not
    /// overwritten.
    ///
    /// Supplying a nickname takes the profile out of anonymity. Going back is
    /// explicit, from the SDK's own profile screen.
    @discardableResult
    public static func setUser(
        nickname: String? = nil,
        avatarUrl: String? = nil,
        bio: String? = nil
    ) async throws -> CommunityUser {
        let profile = try await Factory.repository().setUser(
            nickname: nickname,
            avatarUrl: avatarUrl,
            bio: bio
        )
        // A mounted header and profile screen would keep the old identity.
        NotificationCenter.default.post(name: .appwinCommunityUiRefresh, object: nil)
        return CommunityUser(profile)
    }

    /// Unread notification count, for a badge on the host app's tab.
    ///
    /// To keep a badge current, prefer `unreadNotificationCountUpdates`.
    /// Returns `0` on failure rather than throwing: a badge is an ornament and
    /// must never break the rendering of a tab bar.
    public static func unreadNotificationCount() async -> Int {
        do {
            let bootstrap = try await Factory.repository().bootstrap()
            return bootstrap.unreadNotificationCount
        } catch {
            return 0
        }
    }

    // MARK: - Presentation

    /// SwiftUI view of the feed, to embed in the host app's hierarchy.
    ///
    /// This is the expected integration: a tab of the main bar rendering the
    /// community full page.
    ///
    /// ```swift
    /// TabView {
    ///   AppwinCommunity.communityView()
    ///     .tabItem { Label("Community", systemImage: "bubble.left.and.bubble.right") }
    /// }
    /// ```
    ///
    /// While Community is not ready it shows a "coming soon" placeholder (with
    /// a diagnosis card in debug builds), and it swaps to the feed by itself
    /// when the verdict changes. Use `communityView(unavailable:)` to supply
    /// your own placeholder.
    public static func communityView() -> AnyView {
        communityView { CommunityUnavailableView(result: $0) }
    }

    /// `communityView()` with your own UI while Community is not ready.
    ///
    /// `unavailable` receives `lastResult` (`nil` when `initialize()` has not
    /// run yet). The view stays live: it switches between your placeholder and
    /// the feed as the verdict changes, without remounting.
    ///
    /// ```swift
    /// AppwinCommunity.communityView { _ in
    ///   ComingSoonView()
    /// }
    /// ```
    public static func communityView<Unavailable: View>(
        @ViewBuilder unavailable: @escaping (AppwinInitResult?) -> Unavailable
    ) -> AnyView {
        AnyView(CommunityGateView(unavailable: unavailable))
    }

    /// The feed as a `UIViewController`, for UIKit apps and the Flutter
    /// bridge. Same screen and same live behaviour as `communityView()`.
    ///
    /// - Parameter unavailable: builds the controller shown while Community is
    ///   not ready, from `lastResult`. `nil` shows the SDK's placeholder.
    public static func communityViewController(
        unavailable: ((AppwinInitResult?) -> UIViewController)? = nil
    ) -> UIViewController {
        guard let unavailable else {
            return UIHostingController(rootView: communityView())
        }
        return UIHostingController(rootView: communityView { result in
            CommunityHostedUnavailable(result: result, make: unavailable)
                // A new reason gets a freshly built controller.
                .id(result.map { String(describing: $0) } ?? "nil")
                .ignoresSafeArea()
        })
    }

    /// Presents the community full screen over the host app.
    ///
    /// For apps with no dedicated tab (a menu button, a push notification).
    /// Adds a close button, which the embedded mode does not have.
    public static func presentCommunity() {
        guard isReady else {
            reportNotReady()
            return
        }
        guard let presenter = topViewController() else { return }

        var host: UIHostingController<AppwinCommunityRootView>?
        let root = AppwinCommunityRootView(showsCloseButton: true) {
            host?.dismiss(animated: true)
        }
        let controller = UIHostingController(rootView: root)
        host = controller
        controller.modalPresentationStyle = .fullScreen
        presenter.present(controller, animated: true)
    }

    /// Topmost view controller, to present over.
    static func topViewController() -> UIViewController? {
        let scene = UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .first { $0.activationState == .foregroundActive }
        guard var top = scene?.windows.first(where: \.isKeyWindow)?.rootViewController else {
            return nil
        }
        while let presented = top.presentedViewController {
            top = presented
        }
        return top
    }
}

/// Public view of a member, returned by `setUser`.
///
/// A dedicated type rather than the internal entity, so the SDK's domain can
/// change without breaking the public API or the Flutter bridge.
public struct CommunityUser: Sendable {
    public let id: String
    public let nickname: String
    public let avatarUrl: String?
    public let bio: String?
    public let isAnonymous: Bool
    public let postCount: Int
    public let commentCount: Int
    public let receivedReactionCount: Int

    init(_ profile: CommunityProfile) {
        self.id = profile.id
        self.nickname = profile.nickname
        self.avatarUrl = profile.avatarUrl?.absoluteString
        self.bio = profile.bio
        self.isAnonymous = profile.isAnonymous
        self.postCount = profile.postCount
        self.commentCount = profile.commentCount
        self.receivedReactionCount = profile.receivedReactionCount
    }

    /// Shape carried over a Flutter method channel.
    public var asDictionary: [String: Any] {
        [
            "id": id,
            "nickname": nickname,
            "avatarUrl": avatarUrl as Any,
            "bio": bio as Any,
            "isAnonymous": isAnonymous,
            "postCount": postCount,
            "commentCount": commentCount,
            "receivedReactionCount": receivedReactionCount,
        ]
    }
}
