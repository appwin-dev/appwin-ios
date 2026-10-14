import Foundation
import UIKit
import AppwinCore

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
  private var lifecycleObservers: [NSObjectProtocol] = []
  private var deferredRefetch: Task<Void, Never>?
  private var requestPushOnStart = true

  private init() {}

  func start(requestPushPermission: Bool) async {
    guard AppwinNotifications.isReady else { return }
    guard !started else { return }
    started = true
    requestPushOnStart = requestPushPermission

    installLifecycleObservers()

    try? await AppwinNotifications.trackEvent(.sessionStart)
    if requestPushPermission {
      _ = try? await AppwinNotifications.requestPushAuthorization()
    } else {
      PushRegistration.shared.ensureNotificationDelegate()
    }
    await NotificationsPushHandler.flushPendingPushClick()
    await syncAndPresent()
    scheduleDeferredRefetch()
  }

  func stop() {
    for observer in lifecycleObservers {
      NotificationCenter.default.removeObserver(observer)
    }
    lifecycleObservers = []
    deferredRefetch?.cancel()
    deferredRefetch = nil
    started = false
  }

  /// Tracks `app_open` then presents pending messages (lifecycle / foreground).
  func syncAndPresent() async {
    guard AppwinNotifications.isReady else { return }
    do {
      let messages = try await AppwinNotifications.syncOnAppOpen()
      InAppMessagePresenter.shared.enqueue(messages)
    } catch {
      // In-app messages are ornaments: a failed fetch must not break the app.
    }
  }

  /// Fetches pending messages without tracking `app_open` (realtime delivery).
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
    let center = NotificationCenter.default
    lifecycleObservers = [
      center.addObserver(
        forName: UIApplication.willEnterForegroundNotification,
        object: nil,
        queue: .main
      ) { _ in
        Task { @MainActor in await NotificationsCoordinator.shared.onForeground() }
      },
      center.addObserver(
        forName: UIApplication.didEnterBackgroundNotification,
        object: nil,
        queue: .main
      ) { _ in
        Task { @MainActor in await NotificationsCoordinator.shared.onBackground() }
      },
    ]
  }

  private func onForeground() async {
    PushRegistration.shared.ensureNotificationDelegate()
    if InAppMessagePresenter.shared.consumeSuppressNextAppOpen() {
      await fetchAndPresent()
    } else {
      await syncAndPresent()
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
    try? await AppwinNotifications.trackEvent(.appBackground)
  }
}
