import Foundation
#if canImport(UIKit)
import UIKit
#endif

/// The one observer of the app's foreground and background transitions in
/// the SDK (ADR-0061): every product subscribes here instead of watching
/// UIApplication itself. Handlers run on the main actor. `didBecomeActive`
/// rather than `willEnterForeground`: only the former fires on a cold launch.
///
/// A foreground is the launch activation or an activation that follows a real
/// `didEnterBackground`. The others (Control Center, a system alert, the
/// notification shade) are inactive-then-active blips and are ignored, so no
/// subscriber reconnects or refetches for them. A subscriber arriving after
/// the launch activation does not get it replayed.
@_spi(Appwin) public enum AppLifecycle {
  /// Keep the returned token: releasing it unsubscribes.
  @MainActor
  public static func subscribe(
    onForeground: @escaping @MainActor () -> Void,
    onBackground: @escaping @MainActor () -> Void
  ) -> AnyObject {
    installObserversIfNeeded()
    let subscription = Subscription(onForeground: onForeground, onBackground: onBackground)
    subscriptions.append(WeakSubscription(subscription))
    return subscription
  }

  // MARK: - Registry

  private final class Subscription {
    let onForeground: @MainActor () -> Void
    let onBackground: @MainActor () -> Void

    init(onForeground: @escaping @MainActor () -> Void, onBackground: @escaping @MainActor () -> Void) {
      self.onForeground = onForeground
      self.onBackground = onBackground
    }
  }

  private struct WeakSubscription {
    weak var value: Subscription?
    init(_ value: Subscription) { self.value = value }
  }

  @MainActor private static var subscriptions: [WeakSubscription] = []
  @MainActor private static var observers: [NSObjectProtocol] = []
  /// True until the launch activation, and again after each background.
  @MainActor private static var foregroundPending = false

  /// Test seam: drops the observers and re-arms the process state.
  @MainActor
  static func reset(launchPending: Bool) {
    observers.forEach(NotificationCenter.default.removeObserver)
    observers = []
    subscriptions = []
    installObserversIfNeeded(launchPending: launchPending)
  }

  /// Live subscribers, in subscription order; released tokens are dropped.
  @MainActor
  private static func live() -> [Subscription] {
    subscriptions.removeAll { $0.value == nil }
    return subscriptions.compactMap(\.value)
  }

  @MainActor
  private static func installObserversIfNeeded(launchPending: Bool? = nil) {
    #if canImport(UIKit)
    guard observers.isEmpty else { return }
    // Not active yet (inactive during launch, or background): the launch
    // activation is still to come.
    foregroundPending = launchPending ?? (UIApplication.shared.applicationState != .active)
    let center = NotificationCenter.default
    // UIKit posts on the main thread; `queue: nil` keeps delivery synchronous.
    observers = [
      center.addObserver(forName: UIApplication.didBecomeActiveNotification, object: nil, queue: nil) { _ in
        MainActor.assumeIsolated {
          guard foregroundPending else { return }
          foregroundPending = false
          for subscription in live() { subscription.onForeground() }
        }
      },
      center.addObserver(forName: UIApplication.didEnterBackgroundNotification, object: nil, queue: nil) { _ in
        MainActor.assumeIsolated {
          foregroundPending = true
          for subscription in live() { subscription.onBackground() }
        }
      },
    ]
    #endif
  }
}
