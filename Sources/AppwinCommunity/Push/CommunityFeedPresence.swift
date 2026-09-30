import Combine
import Foundation

/// One mounted feed, as seen by the push and `openPost` routing.
@MainActor
final class CommunityFeedHandle: ObservableObject {
    /// On screen right now, as opposed to mounted in a tab the member left.
    var isVisible = false
    /// A passthrough, not a published value: a target is a one-shot intent,
    /// and replaying the last one to a re-subscribing view would reopen it.
    let targets = PassthroughSubject<CommunityPushTarget, Never>()
}

/// Which feeds are mounted. Held weakly: a feed's handle is its `@StateObject`,
/// so it goes away with the view and needs no unregister call.
@MainActor
enum CommunityFeedPresence {
    private struct Entry {
        weak var handle: CommunityFeedHandle?
    }

    private static var entries: [Entry] = []

    /// How long `deliver` waits for a feed to mount before giving up on it.
    ///
    /// The documented host flow is "switch to the Community tab, then
    /// `openPost`", and `TabView` builds a tab only when it is first shown: at
    /// the `openPost` call the feed usually does not exist yet.
    static var mountGraceNanoseconds: UInt64 = 600_000_000

    private static var pending: CommunityPushTarget?
    private static var pendingExpiry: Task<Void, Never>?

    /// Registers a feed, and hands it the target still waiting for one.
    static func register(_ handle: CommunityFeedHandle) -> CommunityPushTarget? {
        prune()
        if !entries.contains(where: { $0.handle === handle }) {
            entries.append(Entry(handle: handle))
        }
        guard let target = pending else { return nil }
        pending = nil
        pendingExpiry?.cancel()
        pendingExpiry = nil
        return target
    }

    /// Sends `target` to a mounted feed, or waits `mountGraceNanoseconds` for
    /// one to mount before calling `fallback`.
    static func deliver(
        _ target: CommunityPushTarget,
        fallback: @escaping @MainActor (CommunityPushTarget) -> Void
    ) {
        if let feed = mounted {
            feed.targets.send(target)
            return
        }
        pending = target
        pendingExpiry?.cancel()
        pendingExpiry = Task {
            try? await Task.sleep(nanoseconds: mountGraceNanoseconds)
            guard !Task.isCancelled, let waiting = pending else { return }
            pending = nil
            pendingExpiry = nil
            fallback(waiting)
        }
    }

    static var visible: CommunityFeedHandle? {
        prune()
        return entries.last(where: { $0.handle?.isVisible == true })?.handle
    }

    /// The visible feed, else the most recently mounted one.
    static var mounted: CommunityFeedHandle? {
        visible ?? entries.last?.handle
    }

    private static func prune() {
        entries.removeAll { $0.handle == nil }
    }

    /// Test seam: the registry is process-wide.
    static func reset() {
        entries = []
        pending = nil
        pendingExpiry?.cancel()
        pendingExpiry = nil
    }
}
