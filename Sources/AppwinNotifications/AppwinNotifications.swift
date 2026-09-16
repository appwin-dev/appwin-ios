import Foundation
import UIKit
import AppwinCore

/// Appwin Notifications SDK: push, in-app messages, automations.
///
/// Intercom model: after `configure` + `initialize`, call `start()` once and the
/// SDK owns push registration, lifecycle events, realtime delivery and in-app UI.
@MainActor
public enum AppwinNotifications {
  /// Prepares Notifications for this app, and says whether it may be used.
  ///
  /// Call it after `AppwinCore.configure(projectAppId:)` and before `start()`.
  @discardableResult
  public static func initialize() async -> AppwinInitResult {
    let result = await AppwinCore.availability(of: .notifications)
    isReady = result.isReady
    if !result.isReady { AppwinCore.reportUnavailable(.notifications, result) }
    else { AppwinCore.reportMissingPushToken(for: .notifications) }
    return result
  }

  /// Whether `initialize()` has returned `.ready`.
  public private(set) static var isReady = false

  /// Starts push registration, lifecycle hooks, realtime and in-app presentation.
  ///
  /// ```swift
  /// AppwinCore.configure(projectAppId: appId)
  /// if await AppwinNotifications.initialize().isReady {
  ///   await AppwinNotifications.start()
  /// }
  /// ```
  public static func start(requestPushPermission: Bool = true) async {
    await NotificationsCoordinator.shared.start(requestPushPermission: requestPushPermission)
  }

  /// Stops lifecycle observers and the in-app presenter wiring.
  public static func stop() {
    NotificationsCoordinator.shared.stop()
  }

  /// Forward silent pushes here so in-app messages arrive live mid-session.
  ///
  /// Call it from your AppDelegate and enable the Remote notifications
  /// background mode:
  ///
  /// ```swift
  /// func application(
  ///   _ application: UIApplication,
  ///   didReceiveRemoteNotification userInfo: [AnyHashable: Any]
  /// ) async -> UIBackgroundFetchResult {
  ///   if await AppwinNotifications.handleRemoteNotification(userInfo) { return .newData }
  ///   return .noData
  /// }
  /// ```
  ///
  /// Returns `true` when the push was Appwin's nudge (consumed), `false`
  /// otherwise so your own handling can proceed. Optional: without it,
  /// in-app messages are simply delivered at the next app open.
  @discardableResult
  public static func handleRemoteNotification(_ userInfo: [AnyHashable: Any]) async -> Bool {
    guard userInfo["appwinType"] as? String == "inapp.pending" else { return false }
    await NotificationsCoordinator.shared.fetchAndPresent()
    return true
  }

  /// Requests push permission, registers with APNs and forwards the token.
  @discardableResult
  public static func requestPushAuthorization() async throws -> Bool {
    try await PushRegistration.shared.requestAuthorization()
  }

  /// Re-applies the push notification delegate (call early in AppDelegate on Flutter apps).
  public static func ensurePushNotificationDelegate() {
    PushRegistration.shared.ensureNotificationDelegate()
  }

  /// Forwards the APNs device token from `AppDelegate`. Prefer `start()` which
  /// registers this hook automatically when the host uses swizzling-free integration.
  public static func application(
    _ application: UIApplication,
    didRegisterForRemoteNotificationsWithDeviceToken deviceToken: Data
  ) async {
    await PushRegistration.shared.registerDeviceToken(deviceToken)
  }

  public static func application(
    _ application: UIApplication,
    didFailToRegisterForRemoteNotificationsWithError error: Error
  ) {
    PushRegistration.shared.handleRegistrationFailure()
  }

  /// Registers the push token (APNs/FCM) with the server.
  ///
  /// Prefer [AppwinCore.registerPushToken] directly. This wrapper remains for
  /// internal hooks (`PushRegistration`, FCM services) and legacy call sites.
  public static func registerPushToken(
    _ token: String,
    platform: String = "ios",
    pushOptIn: Bool = true
  ) async throws {
    try await AppwinCore.registerPushToken(token, platform: platform, pushOptIn: pushOptIn)
  }

  /// Fetches the in-app messages pending for this device.
  public static func fetchPendingMessages() async throws -> [InAppMessage] {
    guard let client = AppwinCore.client else {
      throw AppwinNotificationsError.notConfigured
    }
    return try await client.request(
      path: "/api/sdk/notifications/v1/messages",
      httpMethod: .get
    )
  }

  /// Tracks a message being opened, clicked or dismissed.
  public static func track(
    deliveryId: String,
    event: TrackEvent,
    buttonIndex: Int? = nil
  ) async throws {
    guard let client = AppwinCore.client else {
      throw AppwinNotificationsError.notConfigured
    }
    struct Body: Encodable {
      let deliveryId: String
      let event: String
      let buttonIndex: Int?
    }
    try await client.requestVoid(
      path: "/api/sdk/notifications/v1/track",
      httpMethod: .post,
      body: Body(deliveryId: deliveryId, event: event.rawValue, buttonIndex: buttonIndex)
    )
  }

  /// Sends an SDK event to trigger automations.
  public static func trackEvent(
    _ event: AutomationEvent,
    eventName: String? = nil,
    properties: [String: String]? = nil
  ) async throws {
    guard let client = AppwinCore.client else {
      throw AppwinNotificationsError.notConfigured
    }
    struct Body: Encodable {
      let event: String
      let eventName: String?
      let properties: [String: String]?
    }
    struct Response: Decodable { let ok: Bool }
    _ = try await client.request(
      path: "/api/sdk/notifications/v1/events",
      httpMethod: .post,
      body: Body(event: event.rawValue, eventName: eventName, properties: properties)
    ) as Response
  }

  /// Tracks `app_open`, then fetches the pending in-app messages.
  public static func syncOnAppOpen() async throws -> [InAppMessage] {
    try await trackEvent(.appOpen)
    return try await fetchPendingMessages()
  }

  /// Fetches pending messages and presents them with the built-in UI.
  public static func presentPendingMessages() async throws {
    let messages = try await fetchPendingMessages()
    InAppMessagePresenter.shared.enqueue(messages)
  }
}
