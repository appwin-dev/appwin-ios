import Foundation
import UIKit
import AppwinCore

/// Wires lifecycle hooks, realtime delivery, and in-app presentation after [AppwinNotifications.start].
@MainActor
final class NotificationsCoordinator {
  static let shared = NotificationsCoordinator()

  private var started = false
  private var lifecycleObservers: [NSObjectProtocol] = []
  private var realtimeSubIds: [UUID] = []
  private var requestPushOnStart = true

  private init() {}

  func start(requestPushPermission: Bool) async {
    guard AppwinNotifications.isReady else { return }
    guard !started else { return }
    started = true
    requestPushOnStart = requestPushPermission

    installLifecycleObservers()
    installRealtime()

    try? await AppwinNotifications.trackEvent(.sessionStart)
    if requestPushPermission {
      _ = try? await AppwinNotifications.requestPushAuthorization()
    }
    await refreshAndPresent()
  }

  func stop() {
    for observer in lifecycleObservers {
      NotificationCenter.default.removeObserver(observer)
    }
    lifecycleObservers = []
    if let hub = AppwinCore.realtimeHub() {
      for id in realtimeSubIds { hub.off(id) }
    }
    realtimeSubIds = []
    started = false
  }

  func refreshAndPresent() async {
    guard AppwinNotifications.isReady else { return }
    do {
      let messages = try await AppwinNotifications.syncOnAppOpen()
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
    await refreshAndPresent()
  }

  private func onBackground() async {
    try? await AppwinNotifications.trackEvent(.appBackground)
  }

  private func installRealtime() {
    guard let hub = AppwinCore.realtimeHub() else { return }
    realtimeSubIds.append(
      hub.on(event: "notifications.message.pending") { _ in
        Task { @MainActor in
          await NotificationsCoordinator.shared.refreshAndPresent()
        }
      }
    )
    realtimeSubIds.append(
      hub.onConnected {
        Task { @MainActor in
          await NotificationsCoordinator.shared.refreshAndPresent()
        }
      }
    )
    hub.start()
  }
}
