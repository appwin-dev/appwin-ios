import Foundation
import UIKit
@_spi(Appwin) import AppwinCore

/// Wires lifecycle hooks and in-app presentation after [AppwinNotifications.start].
///
/// No realtime socket: pending in-app messages are fetched on every
/// foreground, plus one deferred refetch that covers the only case a socket
/// was buying - an automation evaluated asynchronously just after `app_open`,
/// whose message lands seconds after the first fetch. A campaign launched
/// mid-session is delivered at the next open (or by push, its own channel).
@MainActor
final class NotificationsCoordinator {
  static let shared = NotificationsCoordinator()

  /// Covers the async-automation race after an open; one shot, not a poll.
  private static let deferredRefetchDelay: TimeInterval = 5

  private var started = false
  private var lifecycleToken: AnyObject?
  private var deferredRefetch: Task<Void, Never>?
  private var requestPushOnStart = true

  private init() {}

  func start(requestPushPermission: Bool) async {
    guard AppwinNotifications.isReady else { return }
    guard !started else { return }
    started = true
    requestPushOnStart = requestPushPermission

    // Not active yet: the launch foreground is still to come and does the
    // sync and the deferred refetch, so `start()` must not do them twice.
    let launchForegroundComing = UIApplication.shared.applicationState != .active
    installLifecycleObservers()

    if requestPushPermission {
      _ = try? await AppwinNotifications.requestPushAuthorization()
    } else {
      PushRegistration.shared.ensureNotificationDelegate()
    }
    await NotificationsPushHandler.flushPendingPushClick()
    if !launchForegroundComing {
      await fetchAndPresent()
      scheduleDeferredRefetch()
    }
  }

  func stop() {
    lifecycleToken = nil
    deferredRefetch?.cancel()
    deferredRefetch = nil
    started = false
  }

  /// Fetches the pending messages and presents them (foreground, deferred refetch).
  func fetchAndPresent() async {
    guard AppwinNotifications.isReady else { return }
    do {
      let messages = try await AppwinNotifications.fetchPendingMessages()
      InAppMessagePresenter.shared.enqueue(messages)
    } catch {
      // In-app messages are ornaments: a failed fetch must not break the app.
    }
  }

  private func installLifecycleObservers() {
    lifecycleToken = AppLifecycle.subscribe(
      onForeground: { Task { await NotificationsCoordinator.shared.onForeground() } },
      onBackground: { Task { await NotificationsCoordinator.shared.onBackground() } })
  }

  private func onForeground() async {
    PushRegistration.shared.ensureNotificationDelegate()
    if InAppMessagePresenter.shared.consumeSuppressNextAppOpen() {
      await fetchAndPresent()
    } else {
      await fetchAndPresent()
    }
    scheduleDeferredRefetch()
  }

  private func scheduleDeferredRefetch() {
    deferredRefetch?.cancel()
    deferredRefetch = Task { @MainActor in
      try? await Task.sleep(nanoseconds: UInt64(Self.deferredRefetchDelay * 1_000_000_000))
      guard !Task.isCancelled else { return }
      await self.fetchAndPresent()
    }
  }

  private func onBackground() async {
    deferredRefetch?.cancel()
    deferredRefetch = nil
  }
}
