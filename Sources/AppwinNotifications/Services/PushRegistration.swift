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
    let center = UNUserNotificationCenter.current()
    center.delegate = self
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

  // MARK: - UNUserNotificationCenterDelegate

  nonisolated func userNotificationCenter(
    _ center: UNUserNotificationCenter,
    willPresent notification: UNNotification
  ) async -> UNNotificationPresentationOptions {
    [.banner, .sound, .badge]
  }

  nonisolated func userNotificationCenter(
    _ center: UNUserNotificationCenter,
    didReceive response: UNNotificationResponse
  ) async {
    let userInfo = response.notification.request.content.userInfo
    let deliveryId = userInfo["deliveryId"] as? String
    let deeplink = userInfo["deeplink"] as? String
    await MainActor.run {
      Task {
        if let deliveryId {
          try? await AppwinNotifications.track(deliveryId: deliveryId, event: .clicked)
        }
        if let deeplink, let url = URL(string: deeplink) {
          await UIApplication.shared.open(url)
        }
      }
    }
  }
}
