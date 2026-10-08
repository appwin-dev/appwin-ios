import Foundation
import UIKit

/// Shared unread notification count behind
/// `AppwinCommunity.unreadNotificationCountUpdates`.
///
/// Every bootstrap already carries the count, so most updates are free; the
/// store only goes to the network itself on a push, on foreground, and when a
/// consumer subscribes, and only while someone is listening.
@MainActor
enum UnreadCountStore {
    /// Foreground revalidation is the only trigger that fires on its own, and
    /// app switching can fire it many times a minute.
    static let foregroundThrottle: TimeInterval = 30

    private(set) static var value: Int?
    private static var subscribers: [UUID: AsyncStream<Int>.Continuation] = [:]
    private static var lastRefresh: Date?
    private static var refreshing: Task<Void, Never>?
    private static var foregroundObserver: NSObjectProtocol?

    static func update(_ count: Int) {
        guard value != count else { return }
        value = count
        subscribers.values.forEach { $0.yield(count) }
    }

    static func stream() -> AsyncStream<Int> {
        let (stream, continuation) = AsyncStream.makeStream(
            of: Int.self,
            bufferingPolicy: .bufferingNewest(1)
        )
        let id = UUID()
        subscribers[id] = continuation
        continuation.onTermination = { _ in
            Task { @MainActor in subscribers[id] = nil }
        }
        if let value { continuation.yield(value) }
        observeForeground()
        refresh()
        return stream
    }

    /// Something changed server-side (a push, the notifications screen).
    static func refresh() {
        guard !subscribers.isEmpty, AppwinCommunity.isReady, refreshing == nil else { return }
        lastRefresh = Date()
        refreshing = Task {
            // The repository feeds `update` from every bootstrap.
            _ = try? await Factory.repository().bootstrap()
            refreshing = nil
        }
    }

    private static func observeForeground() {
        guard foregroundObserver == nil else { return }
        foregroundObserver = NotificationCenter.default.addObserver(
            forName: UIApplication.willEnterForegroundNotification,
            object: nil,
            queue: .main
        ) { _ in
            Task { @MainActor in
                if let lastRefresh, Date().timeIntervalSince(lastRefresh) < foregroundThrottle { return }
                refresh()
            }
        }
    }
}
