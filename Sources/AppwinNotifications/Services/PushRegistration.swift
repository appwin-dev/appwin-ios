import AppwinCore
import Foundation
import UserNotifications
import UIKit

/// Registers for push, forwards APNs tokens, and hands notifications to `AppwinPush`.
///
/// The notification delegate chains rather than replaces: `UNUserNotificationCenter`
/// has a single delegate slot, and taking it from the host app (or from Firebase)
/// silently broke their own notifications. Whatever is not Appwin's goes to the
/// delegate that was there before.
@MainActor
final class PushRegistration: NSObject, UNUserNotificationCenterDelegate {
  static let shared = PushRegistration()

  private(set) var lastToken: String?
  private(set) var pushOptIn = false

  /// `false` once the host opted out with `start(installsNotificationDelegate: false)`:
  /// it forwards to `AppwinPush` itself, and the wrappers' automatic
  /// `ensurePushNotificationDelegate()` calls must not take the slot back.
  private var installsDelegate = true

  private let chain = DelegateChain()

  private override init() {
    super.init()
  }

  func requestAuthorization() async throws -> Bool {
    ensureNotificationDelegate()
    let center = UNUserNotificationCenter.current()
    let settings = await center.notificationSettings()
    let granted: Bool
    switch settings.authorizationStatus {
    case .authorized, .provisional, .ephemeral:
      granted = true
    case .notDetermined:
      granted = try await center.requestAuthorization(options: [.alert, .badge, .sound])
      if granted {
        try? await AppwinNotifications.trackEvent(.pushOptIn)
      }
    case .denied:
      granted = false
    @unknown default:
      granted = false
    }
    pushOptIn = granted
    // Always re-register when allowed: a reinstall / bundle change needs a
    // fresh APNs token even if permission was already granted.
    if granted {
      UIApplication.shared.registerForRemoteNotifications()
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

  /// Takes the delegate slot, keeping whoever held it as the next link.
  ///
  /// Re-applied on every foreground because Firebase / FlutterFire set their own
  /// delegate after launch.
  func ensureNotificationDelegate() {
    guard installsDelegate else { return }
    let center = UNUserNotificationCenter.current()
    guard center.delegate !== self else { return }
    chain.previous = center.delegate
    center.delegate = self
  }

  /// Forwarding mode: gives the slot back to the delegate we displaced.
  func setInstallsDelegate(_ installs: Bool) {
    installsDelegate = installs
    guard !installs else { return }
    let center = UNUserNotificationCenter.current()
    if center.delegate === self {
      center.delegate = chain.previous
    }
    chain.previous = nil
  }

  // MARK: - UNUserNotificationCenterDelegate

  nonisolated func userNotificationCenter(
    _ center: UNUserNotificationCenter,
    willPresent notification: UNNotification
  ) async -> UNNotificationPresentationOptions {
    let content = notification.request.content
    if let payload = AppwinPushPayload(content.userInfo, title: content.title, body: content.body) {
      let shown = await AppwinPush.handleForeground(payload)
      return shown ? [] : Self.defaultPresentation
    }
    let id = notification.request.identifier
    guard let previous = chain.beginForwarding(id) else { return Self.defaultPresentation }
    defer { chain.endForwarding(id) }
    let willPresent = #selector(
      UNUserNotificationCenterDelegate.userNotificationCenter(_:willPresent:withCompletionHandler:)
    )
    guard previous.responds(to: willPresent) else { return Self.defaultPresentation }
    // The completion-handler form, not `await previous.userNotificationCenter?(...)`:
    // the async form of an optional ObjC requirement crashes swift-frontend 6.3.
    return await withCheckedContinuation { continuation in
      let once = ResumeOnce()
      previous.userNotificationCenter?(center, willPresent: notification) { options in
        if once.claim() { continuation.resume(returning: options) }
      }
    }
  }

  nonisolated func userNotificationCenter(
    _ center: UNUserNotificationCenter,
    didReceive response: UNNotificationResponse
  ) async {
    let userInfo = response.notification.request.content.userInfo
    if let payload = AppwinPushPayload(userInfo) {
      // Swiping the notification away is not a tap.
      guard response.actionIdentifier != UNNotificationDismissActionIdentifier else { return }
      await AppwinPush.handleTap(payload)
      return
    }
    let id = response.notification.request.identifier
    guard let previous = chain.beginForwarding(id) else { return }
    defer { chain.endForwarding(id) }
    let didReceive = #selector(
      UNUserNotificationCenterDelegate.userNotificationCenter(_:didReceive:withCompletionHandler:)
    )
    guard previous.responds(to: didReceive) else { return }
    await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
      let once = ResumeOnce()
      previous.userNotificationCenter?(center, didReceive: response) {
        if once.claim() { continuation.resume() }
      }
    }
  }

  nonisolated func userNotificationCenter(
    _ center: UNUserNotificationCenter,
    openSettingsFor notification: UNNotification?
  ) {
    chain.previous?.userNotificationCenter?(center, openSettingsFor: notification)
  }

  private nonisolated static let defaultPresentation: UNNotificationPresentationOptions = [
    .banner, .sound, .badge,
  ]
}

/// The displaced delegate, readable from the nonisolated delegate callbacks.
///
/// Also breaks forwarding loops: a delegate that captured us as *its* previous
/// one (FlutterFire does) would bounce a notification back here forever. A
/// notification already being forwarded is not forwarded again.
private final class DelegateChain: @unchecked Sendable {
  private let lock = NSLock()
  private weak var _previous: UNUserNotificationCenterDelegate?
  private var inFlight: Set<String> = []

  var previous: UNUserNotificationCenterDelegate? {
    get { lock.withLock { _previous } }
    set { lock.withLock { _previous = newValue } }
  }

  func beginForwarding(_ id: String) -> UNUserNotificationCenterDelegate? {
    lock.withLock {
      guard let previous = _previous, inFlight.insert(id).inserted else { return nil }
      return previous
    }
  }

  func endForwarding(_ id: String) {
    lock.withLock { _ = inFlight.remove(id) }
  }
}

/// A delegate that calls its completion handler twice must not crash the host
/// through our continuation.
private final class ResumeOnce: @unchecked Sendable {
  private let lock = NSLock()
  private var claimed = false

  func claim() -> Bool {
    lock.withLock {
      defer { claimed = true }
      return !claimed
    }
  }
}
