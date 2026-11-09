import Foundation
import os

/// Core's internal bus (ADR-0061): every event of the flow reaches the
/// products installed in the app, each subscriber under the consent purpose
/// it needs. Not public.
final class EventBus: @unchecked Sendable {
  struct Event: Sendable {
    let name: String
    let eventId: String
    let props: [String: AnalyticsValue]?
  }

  private struct Subscription {
    let purpose: ConsentPurpose?
    let handler: @Sendable (Event) -> Void
  }

  /// Dropping the token unsubscribes.
  private final class Token {
    let id: UUID
    weak var bus: EventBus?
    init(id: UUID, bus: EventBus) {
      self.id = id
      self.bus = bus
    }
    deinit { bus?.remove(id) }
  }

  private let isGranted: @Sendable (ConsentPurpose) -> Bool
  private let subscriptions = OSAllocatedUnfairLock<[UUID: Subscription]>(initialState: [:])

  init(isGranted: @escaping @Sendable (ConsentPurpose) -> Bool) {
    self.isGranted = isGranted
  }

  /// `purpose == nil`: delivered whatever the consent (an OS signal, no
  /// identifier). Otherwise delivered only while the purpose is `granted`,
  /// checked at each publish.
  func subscribe(purpose: ConsentPurpose?, _ handler: @escaping @Sendable (Event) -> Void) -> AnyObject {
    let id = UUID()
    subscriptions.withLock { $0[id] = Subscription(purpose: purpose, handler: handler) }
    return Token(id: id, bus: self)
  }

  func publish(_ event: Event) {
    // Handlers run outside the lock: one may subscribe or publish itself.
    let current = subscriptions.withLock { Array($0.values) }
    for subscription in current {
      if let purpose = subscription.purpose, !isGranted(purpose) { continue }
      subscription.handler(event)
    }
  }

  private func remove(_ id: UUID) {
    subscriptions.withLock { _ = $0.removeValue(forKey: id) }
  }
}

/// Keeps the tokens of a product's subscriptions alive for the process.
final class BusSubscriptions: @unchecked Sendable {
  private let lock = NSLock()
  private var tokens: [AnyObject] = []

  func retain(_ token: AnyObject) {
    lock.lock()
    defer { lock.unlock() }
    tokens.append(token)
  }

  func clear() {
    lock.lock()
    defer { lock.unlock() }
    tokens = []
  }
}
