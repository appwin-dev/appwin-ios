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
    // Register so Community / Core can arm the UN delegate without importing us.
    AppwinCore.pushCapturePreparer = { PushRegistration.shared.ensureNotificationDelegate() }
    AppwinCore.preparePushCapture()
    let result = await AppwinCore.availability(of: .notifications)
    isReady = result.isReady
    if !result.isReady {
      AppwinCore.reportUnavailable(.notifications, result)
      AppwinPush.unregister(.notifications)
    } else {
      AppwinCore.reportMissingPushToken(for: .notifications)
      AppwinPush.register(.notifications, handler: NotificationsPushHandler())
    }
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
  ///
  /// - Parameter installsNotificationDelegate: `false` when your app owns its
  ///   push stack (Firebase Messaging, FlutterFire, your own
  ///   `UNUserNotificationCenterDelegate`) and forwards to `AppwinPush` itself.
  ///   Left `true`, the SDK takes the delegate slot and passes every
  ///   notification that is not Appwin's to the delegate it displaced.
  public static func start(
    requestPushPermission: Bool = true,
    installsNotificationDelegate: Bool = true
  ) async {
    PushRegistration.shared.setInstallsDelegate(installsNotificationDelegate)
    await NotificationsCoordinator.shared.start(requestPushPermission: requestPushPermission)
  }

  /// Stops lifecycle observers and the in-app presenter wiring.
  public static func stop() {
    NotificationsCoordinator.shared.stop()
  }

  /// Requests push permission, registers with APNs and forwards the token.
  @discardableResult
  public static func requestPushAuthorization() async throws -> Bool {
    try await PushRegistration.shared.requestAuthorization()
  }

  /// Installs the SDK's notification delegate now, chained to the current one.
  ///
  /// Call it in `application(_:didFinishLaunchingWithOptions:)`: iOS hands the
  /// tap that launched the app to whichever delegate is set when launch
  /// finishes, and `start()` usually runs later. A no-op after
  /// `start(installsNotificationDelegate: false)`.
  public static func ensurePushNotificationDelegate() {
    AppwinCore.pushCapturePreparer = { PushRegistration.shared.ensureNotificationDelegate() }
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
