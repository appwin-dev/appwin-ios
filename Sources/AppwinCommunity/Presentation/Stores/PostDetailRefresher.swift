import Foundation
@_spi(Appwin) import AppwinCore

/// Which realtime events concern the post whose detail is open.
///
/// The envelope carries no resource, only ids (ADR-0016): the detail refetches
/// over REST. Kept pure so the matching is testable without a socket.
enum PostDetailRealtime {
    static let commentCreated = "community.comment.created"
    static let commentDeleted = "community.comment.deleted"
    static let postUpdated = "community.post.updated"

    static let events = [commentCreated, commentDeleted, postUpdated]

    /// `true` when `payload` (the envelope's `data`) may change what the
    /// detail of `postId` shows.
    ///
    /// Comment events name their post in `changes`; a server from before that
    /// sends no `changes`, and then any comment event refetches rather than
    /// miss one. `post.updated` carries the post id as `resourceId`.
    static func concerns(event: String, payload: Any?, postId: String) -> Bool {
        let data = payload as? [String: Any]
        if let resourceId = data?["resourceId"] as? String, resourceId == postId {
            return true
        }
        if let changes = data?["changes"] as? [String] {
            return changes.contains(postId)
        }
        return event == commentCreated || event == commentDeleted
    }
}

/// Coalesces bursts into one call, `delay` after the last `schedule`.
@MainActor
final class RefreshDebouncer {
    private let delay: TimeInterval
    private var pending: Task<Void, Never>?

    init(delay: TimeInterval) {
        self.delay = delay
    }

    func schedule(_ action: @escaping @MainActor () async -> Void) {
        pending?.cancel()
        let nanoseconds = UInt64(delay * 1_000_000_000)
        pending = Task { [weak self] in
            try? await Task.sleep(nanoseconds: nanoseconds)
            guard !Task.isCancelled else { return }
            self?.pending = nil
            await action()
        }
    }

    func cancel() {
        pending?.cancel()
        pending = nil
    }
}

/// Keeps an open post detail fresh without full realtime: a refetch on a
/// matching realtime event (debounced) and on return to the foreground.
///
/// Lives for the time the detail is on screen: `start` on appear, `stop` on
/// disappear. Without a realtime hub (Core not configured, socket down) only
/// the foreground refetch remains.
@MainActor
final class PostDetailRefresher: ObservableObject {
    /// A comment thread under activity emits in bursts; one refetch covers it.
    static let debounceDelay: TimeInterval = 0.7

    private let debouncer = RefreshDebouncer(delay: PostDetailRefresher.debounceDelay)
    private var subscriptions: [UUID] = []
    private var hub: RealtimeHub?
    private var lifecycleToken: AnyObject?
    private var refresh: (@MainActor () async -> Void)?

    func start(postId: String, refresh: @escaping @MainActor () async -> Void) {
        stop()
        self.refresh = refresh

        // The launch activation is not replayed to a late subscriber, so this
        // only fires on a real return from the background, never on appear.
        lifecycleToken = AppLifecycle.subscribe(
            onForeground: { [weak self] in self?.trigger() },
            onBackground: {}
        )

        guard let realtime = AppwinCore.realtimeHub() else { return }
        hub = realtime
        for event in PostDetailRealtime.events {
            subscriptions.append(realtime.on(event: event) { [weak self] payload in
                guard PostDetailRealtime.concerns(event: event, payload: payload, postId: postId) else {
                    return
                }
                Task { @MainActor in self?.trigger() }
            })
        }
    }

    private func trigger() {
        guard let refresh else { return }
        debouncer.schedule(refresh)
    }

    func stop() {
        for id in subscriptions { hub?.off(id) }
        subscriptions = []
        hub = nil
        lifecycleToken = nil
        refresh = nil
        debouncer.cancel()
    }
}
