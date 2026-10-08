import Foundation
import UIKit

/// Fans the latest verdict out to `AppwinCore.availabilityUpdates(of:)`.
///
/// Fed by every `availability(of:)` call, whichever product made it: the three
/// products share one verdict, so Support's `initialize()` is enough to tell a
/// mounted Community view that its plan lapsed.
@MainActor
enum AvailabilityUpdates {
  private static var latest: [AppwinProduct: AppwinInitResult] = [:]
  private static var subscribers: [AppwinProduct: [UUID: AsyncStream<AppwinInitResult>.Continuation]] = [:]
  private static var foregroundObserver: NSObjectProtocol?

  static func publish(_ verdict: AvailabilityVerdict?) {
    for product in AppwinProduct.allCases {
      publish(AvailabilityStore.result(for: product, in: verdict), for: product)
    }
  }

  private static func publish(_ result: AppwinInitResult, for product: AppwinProduct) {
    // A failed request with nothing cached must not overwrite a verdict this
    // process already holds: offline is not an answer.
    if result == .unknown, latest[product] != nil { return }
    guard latest[product] != result else { return }
    latest[product] = result
    subscribers[product]?.values.forEach { $0.yield(result) }
  }

  static func stream(of product: AppwinProduct, store: AvailabilityStore?) -> AsyncStream<AppwinInitResult> {
    let (stream, continuation) = AsyncStream.makeStream(
      of: AppwinInitResult.self,
      bufferingPolicy: .bufferingNewest(1)
    )
    let id = UUID()
    subscribers[product, default: [:]][id] = continuation
    continuation.onTermination = { _ in
      Task { @MainActor in subscribers[product]?[id] = nil }
    }
    observeForeground()

    if let known = latest[product] {
      continuation.yield(known)
    } else if let store {
      Task {
        guard let cached = await store.cachedVerdict(), latest[product] == nil else { return }
        publish(cached)
      }
    } else {
      continuation.yield(.notConfigured)
    }
    return stream
  }

  /// Revalidates on foreground while someone listens, so a dashboard toggle
  /// reaches a mounted screen without a relaunch. Release builds still honour
  /// the cache TTL inside `AvailabilityStore.fetch`.
  private static func observeForeground() {
    guard foregroundObserver == nil else { return }
    foregroundObserver = NotificationCenter.default.addObserver(
      forName: UIApplication.willEnterForegroundNotification,
      object: nil,
      queue: .main
    ) { _ in
      Task { @MainActor in
        guard let product = subscribers.first(where: { !$0.value.isEmpty })?.key else { return }
        _ = await AppwinCore.availability(of: product)
      }
    }
  }

  /// Test seam: the state is process-wide.
  static func reset() {
    latest = [:]
    subscribers = [:]
  }
}
