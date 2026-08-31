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

    /// Backwards-compatible entry point; delegates to `AppwinCore.configure`.
    ///
    /// Prefer calling `AppwinCore.configure(projectAppId:)` directly when
    /// integrating several Appwin SDKs: Core owns the device identity,
    /// Community is only a consumer.
    public static func initialize(appId: String, baseUrl: String? = nil) {
        AppwinCore.configure(projectAppId: appId, baseUrl: baseUrl)
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
        return CommunityUser(profile)
    }

    /// Attaches the member to the host app's user id.
    ///
    /// The `externalId` is propagated to `AppwinCore`, so the same user is
    /// recognised by Support too.
    public static func login(externalId: String) async throws {
        guard !externalId.isEmpty else {
            throw AppwinCommunityError.invalidArgument("externalId is empty")
        }
        AppwinCore.identify(externalId: externalId)
        // Replay the bootstrap so the bearer carries the new identity;
        // otherwise later calls stay on the anonymous profile until the app is
        // next opened.
        try await AppwinCore.bootstrapSession(externalId: externalId)
    }

    /// Revokes the session and goes back to anonymous.
    public static func logout() async {
        await AppwinCore.signOut()
    }

    /// Unread notification count, for a badge on the host app's tab.
    ///
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
    public static func communityView() -> AnyView {
        AnyView(AppwinCommunityRootView())
    }

    /// The feed as a `UIViewController`, for UIKit apps and the Flutter
    /// bridge. Same screen as `communityView()`.
    public static func communityViewController() -> UIViewController {
        UIHostingController(rootView: AppwinCommunityRootView())
    }

    /// Presents the community full screen over the host app.
    ///
    /// For apps with no dedicated tab (a menu button, a push notification).
    /// Adds a close button, which the embedded mode does not have.
    public static func presentCommunity() {
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
    private static func topViewController() -> UIViewController? {
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
