import Foundation
import UIKit

/// Routes Appwin pushes to the product that owns them.
///
/// **Automatic mode** (default): `AppwinNotifications.start()` installs the SDK's
/// notification delegate, which calls this for you. Nothing to write.
///
/// **Forwarding mode**: your app owns its push stack (Firebase Messaging,
/// FlutterFire, your own `UNUserNotificationCenterDelegate`). Opt out with
/// `AppwinNotifications.start(installsNotificationDelegate: false)` and forward
/// from your own callbacks:
///
/// ```swift
/// func userNotificationCenter(
///   _ center: UNUserNotificationCenter,
///   didReceive response: UNNotificationResponse
/// ) async {
///   let userInfo = response.notification.request.content.userInfo
///   if AppwinPush.handleTap(userInfo) { return }
///   // your own routing
/// }
///
/// func userNotificationCenter(
///   _ center: UNUserNotificationCenter,
///   willPresent notification: UNNotification
/// ) async -> UNNotificationPresentationOptions {
///   if AppwinPush.handleForeground(notification.request.content.userInfo) { return [] }
///   return [.banner, .sound, .badge]
/// }
///
/// func application(
///   _ application: UIApplication,
///   didReceiveRemoteNotification userInfo: [AnyHashable: Any]
/// ) async -> UIBackgroundFetchResult {
///   await AppwinPush.handleMessage(userInfo) ? .newData : .noData
/// }
/// ```
///
/// Mirrors `AppwinPush` on Android.
@MainActor
public enum AppwinPush {

  /// Whether `data` (a notification's `userInfo`, or FCM `data`) is an Appwin push.
  nonisolated public static func isAppwinPush(_ data: [AnyHashable: Any]) -> Bool {
    AppwinPushPayload(data) != nil
  }

  /// The user tapped a notification. Returns `true` when it was Appwin's, which
  /// then handles it: do not route it yourself.
  ///
  /// Safe to call at launch, before any product is initialized: the tap is kept
  /// and replayed as soon as its product is ready.
  @discardableResult
  public static func handleTap(_ data: [AnyHashable: Any]) -> Bool {
    guard let payload = AppwinPushPayload(data) else { return false }
    handleTap(payload)
    return true
  }

  /// A notification arrived while the app is in the foreground. Returns `true`
  /// when Appwin showed its own UI for it (e.g. the Support in-app banner): do
  /// not present the system notification as well.
  ///
  /// Pass `title` and `body` when the push reached you without its `aps`
  /// dictionary (Firebase Messaging hands `data` and the notification text
  /// separately); they win over `aps.alert` otherwise.
  @discardableResult
  public static func handleForeground(
    _ data: [AnyHashable: Any],
    title: String? = nil,
    body: String? = nil
  ) -> Bool {
    guard let payload = AppwinPushPayload(data, title: title, body: body) else { return false }
    return handleForeground(payload)
  }

  /// A data (silent) message reached the app. Returns `true` when Appwin
  /// consumed it, once the work it triggers is done.
  @discardableResult
  public static func handleMessage(_ data: [AnyHashable: Any]) async -> Bool {
    guard let payload = AppwinPushPayload(data) else { return false }
    return await handleMessage(payload)
  }

  // MARK: - Products

  private static var handlers: [String: any AppwinPushHandler] = [:]

  /// At most one tap per product: a tap is a single intent, and replaying an
  /// older one after the newest would open the wrong screen.
  private static var pendingTaps: [String: AppwinPushPayload] = [:]

  private static var reportedWaiting: Set<String> = []

  /// Called by a product once it can act on its pushes. Replays the tap that
  /// launched the app, if one was waiting.
  package static func register(_ product: AppwinProduct, handler: any AppwinPushHandler) {
    handlers[product.rawValue] = handler
    if let pending = pendingTaps.removeValue(forKey: product.rawValue) {
      Task { await handler.onTap(pending) }
    }
  }

  package static func unregister(_ product: AppwinProduct) {
    handlers[product.rawValue] = nil
  }

  package static func handleTap(_ payload: AppwinPushPayload) {
    if let handler = handlers[payload.product] {
      Task { await handler.onTap(payload) }
      return
    }
    pendingTaps[payload.product] = payload
    report(
      "push tap for '\(payload.product)' kept until that product is initialized",
      once: payload.product
    )
  }

  package static func handleForeground(_ payload: AppwinPushPayload) -> Bool {
    handlers[payload.product]?.onForeground(payload) ?? false
  }

  package static func handleMessage(_ payload: AppwinPushPayload) async -> Bool {
    await handlers[payload.product]?.onMessage(payload) ?? false
  }

  /// Opens a deeplink carried by a push or an in-app message.
  ///
  /// `appwin://<product>/...` goes to that product (queued like a tap). Any
  /// other URL goes to the OS. `appwin://` is never handed to the OS: no app
  /// declares that scheme, so iOS would drop it.
  ///
  /// `source` is the product asking, so a route back to itself is dropped
  /// rather than looping.
  package static func openDeeplink(_ url: URL, from source: AppwinProduct? = nil) {
    guard AppwinPushPayload.route(of: url) != nil else {
      UIApplication.shared.open(url)
      return
    }
    guard let payload = AppwinPushPayload(deeplink: url), payload.product != source?.rawValue else {
      report("deeplink \(url.absoluteString) ignored: no product can route it", once: nil)
      return
    }
    handleTap(payload)
  }

  private static func report(_ message: String, once key: String?) {
    #if DEBUG
    if let key {
      guard reportedWaiting.insert(key).inserted else { return }
    }
    print("[Appwin] \(message)")
    #endif
  }

  /// Test seam: the routing state is process-wide.
  static func reset() {
    handlers = [:]
    pendingTaps = [:]
    reportedWaiting = []
  }

  static func pendingTap(for product: String) -> AppwinPushPayload? {
    pendingTaps[product]
  }
}

/// What a product plugs into `AppwinPush`. Adding a product means registering
/// one of these, nothing else.
@MainActor
package protocol AppwinPushHandler: AnyObject {
  /// A tap on one of this product's pushes, possibly replayed after a cold start.
  func onTap(_ payload: AppwinPushPayload) async
  /// Return `true` when the product showed its own UI instead of the system banner.
  func onForeground(_ payload: AppwinPushPayload) -> Bool
  /// Return `true` when the data message was consumed.
  func onMessage(_ payload: AppwinPushPayload) async -> Bool
}

extension AppwinPushHandler {
  package func onForeground(_ payload: AppwinPushPayload) -> Bool { false }
  package func onMessage(_ payload: AppwinPushPayload) async -> Bool { false }
}
