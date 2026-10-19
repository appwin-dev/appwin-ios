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
  //
  // Completion-handler form on purpose (not the Swift `async` one). FlutterFire
  // takes the UN delegate slot and only forwards via
  // `respondsToSelector:…withCompletionHandler:`. The async methods do not
  // answer that selector, so Appwin taps were swallowed and never tracked.

  nonisolated func userNotificationCenter(
    _ center: UNUserNotificationCenter,
    willPresent notification: UNNotification,
    withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void
  ) {
    // UNUserNotificationCenter completion handlers are not Sendable; the system
    // still expects exactly one call, from any queue.
    nonisolated(unsafe) let finish = completionHandler
    let content = notification.request.content
    if let payload = AppwinPushPayload(content.userInfo, title: content.title, body: content.body) {
      Task { @MainActor in
        let shown = AppwinPush.handleForeground(payload)
        finish(shown ? [] : Self.defaultPresentation)
      }
      return
    }
    let id = notification.request.identifier
    guard let previous = chain.beginForwarding(id) else {
      finish(Self.defaultPresentation)
      return
    }
    let willPresent = #selector(
      UNUserNotificationCenterDelegate.userNotificationCenter(_:willPresent:withCompletionHandler:)
    )
    guard previous.responds(to: willPresent) else {
      chain.endForwarding(id)
      finish(Self.defaultPresentation)
      return
    }
    let once = ResumeOnce()
    previous.userNotificationCenter?(center, willPresent: notification) { options in
      self.chain.endForwarding(id)
      if once.claim() { finish(options) }
    }
  }

  nonisolated func userNotificationCenter(
    _ center: UNUserNotificationCenter,
    didReceive response: UNNotificationResponse,
    withCompletionHandler completionHandler: @escaping () -> Void
  ) {
    nonisolated(unsafe) let finish = completionHandler
    let userInfo = response.notification.request.content.userInfo
    if let payload = AppwinPushPayload(userInfo) {
      // Swiping the notification away is not a tap.
      guard response.actionIdentifier != UNNotificationDismissActionIdentifier else {
        finish()
        return
      }
      Task { @MainActor in
        AppwinPush.handleTap(payload)
        finish()
      }
      return
    }
    let id = response.notification.request.identifier
    guard let previous = chain.beginForwarding(id) else {
      finish()
      return
    }
    let didReceive = #selector(
      UNUserNotificationCenterDelegate.userNotificationCenter(_:didReceive:withCompletionHandler:)
    )
    guard previous.responds(to: didReceive) else {
      chain.endForwarding(id)
      finish()
      return
    }
    let once = ResumeOnce()
    previous.userNotificationCenter?(center, didReceive: response) {
      self.chain.endForwarding(id)
      if once.claim() { finish() }
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
