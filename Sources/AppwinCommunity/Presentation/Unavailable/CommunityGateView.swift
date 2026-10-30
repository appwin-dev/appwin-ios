import SwiftUI
import UIKit
@_spi(Appwin) import AppwinCore

/// Community's verdict as the UI sees it, kept current by
/// `AppwinCore.availabilityUpdates(of:)` once `initialize()` has run.
@MainActor
final class CommunityAvailability: ObservableObject {
    static let shared = CommunityAvailability()

    /// `nil` until `AppwinCommunity.initialize()` answers.
    @Published private(set) var result: AppwinInitResult?
    /// Ready only thanks to the debug build: the feed warns that release
    /// builds will not get it.
    @Published private(set) var debugUnlocked = false
    /// Set while the studio's subscription is paused. The result is then
    /// `.ready` (the host keeps its tab), but the feed gives way to the
    /// "on hold" screen.
    @Published private(set) var pause: AppwinPause?

    private var following: Task<Void, Never>?
    private var followingPause: Task<Void, Never>?

    func apply(_ result: AppwinInitResult, pause: AppwinPause? = nil) {
        if self.result != result { self.result = result }
        if self.pause != pause { self.pause = pause }
        // Paused is "not ready" for everything that talks to the server: no
        // push registration, no watcher.
        if result.isReady && pause == nil {
            CommunityPushRouter.shared.registerIfNeeded()
            CommunityInAppWatcher.start()
        } else {
            CommunityPushRouter.shared.unregister()
            CommunityInAppWatcher.stop()
        }
        #if DEBUG
        Task { [weak self] in
            let unlocked = result.isReady ? await AppwinCore.isDebugUnlocked(.community) : false
            // A newer verdict may have landed during the await: its own task decides.
            guard let self, self.result == result, self.debugUnlocked != unlocked else { return }
            self.debugUnlocked = unlocked
        }
        #endif
    }

    func follow() {
        guard following == nil else { return }
        following = Task { [weak self] in
            for await result in AppwinCore.availabilityUpdates(of: .community) {
                // Read from the verdict itself: the pause stream may not have
                // delivered yet, and a stale `nil` would start the push and
                // the watcher of a paused product.
                let pause = await AppwinCore.pause(of: .community)
                self?.apply(result, pause: pause)
            }
        }
        followingPause = Task { [weak self] in
            for await pause in AppwinCore.pauseUpdates(of: .community) {
                guard let self else { continue }
                if let result = self.result { self.apply(result, pause: pause) } else { self.pause = pause }
            }
        }
    }
}

/// Swaps the feed and the unavailable UI as the verdict changes, inside the
/// host's hierarchy: a plan that lapses or a toggle flipped on must not need
/// the host to remount its tab.
struct CommunityGateView<Unavailable: View>: View {
    @ObservedObject private var availability = CommunityAvailability.shared
    let unavailable: (AppwinInitResult?) -> Unavailable
    var profileEditing = ProfileEditingHandlers()

    var body: some View {
        if availability.result?.isReady == true, let pause = availability.pause {
            CommunityPausedView(pause: pause)
        } else if availability.result?.isReady == true {
            AppwinCommunityRootView(profileEditing: profileEditing)
        } else {
            unavailable(availability.result)
                .onAppear { AppwinCommunity.reportNotReady() }
        }
    }
}

/// Hosts a studio-supplied `UIViewController` as the unavailable UI.
struct CommunityHostedUnavailable: UIViewControllerRepresentable {
    let result: AppwinInitResult?
    let make: (AppwinInitResult?) -> UIViewController

    func makeUIViewController(context: Context) -> UIViewController { make(result) }
    func updateUIViewController(_ controller: UIViewController, context: Context) {}
}
