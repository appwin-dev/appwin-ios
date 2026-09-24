import AppwinCore
import Foundation

/// Notifications' side of `AppwinPush`: campaign taps (click tracking, then
/// the campaign's deeplink) and the silent `inapp.pending` nudge.
@MainActor
final class NotificationsPushHandler: AppwinPushHandler {

  func onTap(_ payload: AppwinPushPayload) async {
    if let deliveryId = payload.deliveryId {
      await Self.trackPushClickWhenReady(deliveryId: deliveryId)
    }
    guard let deeplink = payload.deeplink, let url = URL(string: deeplink) else { return }
    AppwinPush.openDeeplink(url, from: .notifications)
  }

  func onMessage(_ payload: AppwinPushPayload) async -> Bool {
    guard payload.type == "inapp.pending" else { return false }
    await NotificationsCoordinator.shared.fetchAndPresent()
    return true
  }

  /// Replays a click stored before AppwinCore was ready (cold start from push).
  static func flushPendingPushClick() async {
    guard let deliveryId = UserDefaults.standard.string(forKey: pendingDeliveryIdKey),
          !deliveryId.isEmpty
    else { return }
    UserDefaults.standard.removeObject(forKey: pendingDeliveryIdKey)
    await trackPushClickWhenReady(deliveryId: deliveryId)
  }

  private static let pendingDeliveryIdKey = "appwin.notifications.pendingPushClickDeliveryId"

  private static func trackPushClickWhenReady(deliveryId: String) async {
    for _ in 0 ..< 20 {
      if AppwinCore.client != nil {
        try? await AppwinNotifications.track(deliveryId: deliveryId, event: .clicked)
        return
      }
      try? await Task.sleep(nanoseconds: 250_000_000)
    }
    UserDefaults.standard.set(deliveryId, forKey: pendingDeliveryIdKey)
  }
}
