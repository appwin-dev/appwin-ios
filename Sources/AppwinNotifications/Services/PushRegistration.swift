import AppwinCore
import Foundation
import UserNotifications
import UIKit

/// Registers for push, forwards APNs tokens, and reports notification interactions.
@MainActor
final class PushRegistration: NSObject, UNUserNotificationCenterDelegate {
  static let shared = PushRegistration()

  private var tokenContinuation: CheckedContinuation<String, Error>?
  private(set) var lastToken: String?
  private(set) var pushOptIn = false

  private override init() {
    super.init()
  }

  func requestAuthorization() async throws -> Bool {
    ensureNotificationDelegate()
    let center = UNUserNotificationCenter.current()
    let granted = try await center.requestAuthorization(options: [.alert, .badge, .sound])
    pushOptIn = granted
    if granted {
      UIApplication.shared.registerForRemoteNotifications()
    }
    if granted {
      try? await AppwinNotifications.trackEvent(.pushOptIn)
    }
    return granted
  }

  func registerDeviceToken(_ deviceToken: Data) async {
    let token = deviceToken.map { String(format: "%02x", $0) }.joined()
    lastToken = token
    guard !token.isEmpty else { return }
    try? await AppwinCore.registerPushToken(token, pushOptIn: pushOptIn)
  }

  func handleRegistrationFailure() {
    lastToken = nil
  }

  /// Re-applies the notification delegate (e.g. after Firebase Messaging overrides it).
  func ensureNotificationDelegate() {
    UNUserNotificationCenter.current().delegate = self
  }

  // MARK: - UNUserNotificationCenterDelegate

  nonisolated func userNotificationCenter(
    _ center: UNUserNotificationCenter,
    willPresent notification: UNNotification
  ) async -> UNNotificationPresentationOptions {
    let userInfo = notification.request.content.userInfo
    let deeplink = Self.extractDeeplink(from: userInfo)
    // Support replies: prefer the custom in-app banner (realtime watcher, or
    // the push payload itself). System banners in foreground replace that UI.
    if let deeplink, let url = URL(string: deeplink),
       AppwinPushRouting.isSupportConversationDeeplink(url) {
      let content = notification.request.content
      let shown = await Self.presentSupportInAppBanner(
        title: content.title,
        body: content.body,
        deeplink: deeplink
      )
      // If the host has no attachable window (classic RN UIWindow), keep the
      // system banner rather than swallowing the notification.
      return shown ? [] : [.banner, .sound, .badge]
    }
    return [.banner, .sound, .badge]
  }

  nonisolated func userNotificationCenter(
    _ center: UNUserNotificationCenter,
    didReceive response: UNNotificationResponse
  ) async {
    let userInfo = response.notification.request.content.userInfo
    let deliveryId = Self.extractDeliveryId(from: userInfo)
    let deeplink = Self.extractDeeplink(from: userInfo)
    await Self.handleNotificationTap(deliveryId: deliveryId, deeplink: deeplink)
  }

  @MainActor
  private static func presentSupportInAppBanner(title: String, body: String, deeplink: String) -> Bool {
    guard let url = URL(string: deeplink),
          let conversationId = AppwinPushRouting.supportConversationId(from: url)
    else { return false }
    let trimmedTitle = title.trimmingCharacters(in: .whitespacesAndNewlines)
    let trimmedBody = body.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !trimmedBody.isEmpty else { return false }
    return AppwinInAppBanner.present(
      AppwinBanner(
        id: "support-push:\(conversationId)",
        title: trimmedTitle.isEmpty ? SupportPushCopy.fallbackTitle : trimmedTitle,
        body: trimmedBody,
        onTap: {
          if let handler = AppwinPushRouting.handleDeeplink, handler(url) {
            return
          }
          UIApplication.shared.open(url)
        }
      )
    )
  }

  @MainActor
  private static func handleNotificationTap(deliveryId: String?, deeplink: String?) async {
    if let deliveryId {
      await trackPushClickWhenReady(deliveryId: deliveryId)
    }
    guard let deeplink, let url = URL(string: deeplink) else { return }
    if let handler = AppwinPushRouting.handleDeeplink, handler(url) {
      return
    }
    await UIApplication.shared.open(url)
  }

  /// Replays a tap stored before AppwinCore was ready (cold start from push).
  func flushPendingPushClick() async {
    let key = Self.pendingDeliveryIdKey
    guard let deliveryId = UserDefaults.standard.string(forKey: key), !deliveryId.isEmpty else {
      return
    }
    UserDefaults.standard.removeObject(forKey: key)
    await Self.trackPushClickWhenReady(deliveryId: deliveryId)
  }

  private static let pendingDeliveryIdKey = "appwin.notifications.pendingPushClickDeliveryId"

  private static func storePendingPushClick(_ deliveryId: String) {
    UserDefaults.standard.set(deliveryId, forKey: pendingDeliveryIdKey)
  }

  nonisolated private static func extractDeliveryId(from userInfo: [AnyHashable: Any]) -> String? {
    if let id = userInfo["deliveryId"] as? String, !id.isEmpty { return id }
    if let data = userInfo["data"] as? [String: Any],
       let id = data["deliveryId"] as? String,
       !id.isEmpty {
      return id
    }
    return nil
  }

  nonisolated private static func extractDeeplink(from userInfo: [AnyHashable: Any]) -> String? {
    if let deeplink = userInfo["deeplink"] as? String, !deeplink.isEmpty { return deeplink }
    if let data = userInfo["data"] as? [String: Any],
       let deeplink = data["deeplink"] as? String,
       !deeplink.isEmpty {
      return deeplink
    }
    return nil
  }

  @MainActor
  private static func trackPushClickWhenReady(deliveryId: String) async {
    for _ in 0 ..< 20 {
      if AppwinCore.client != nil {
        try? await AppwinNotifications.track(deliveryId: deliveryId, event: .clicked)
        return
      }
      try? await Task.sleep(nanoseconds: 250_000_000)
    }
    storePendingPushClick(deliveryId)
  }
}

/// Local fallback when APNs omits a title (Notifications must not import Support).
private enum SupportPushCopy {
  static let fallbackTitle = "Support"
}
