import SwiftUI
import UIKit
import AppwinCore

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

    private var following: Task<Void, Never>?

    func apply(_ result: AppwinInitResult) {
        if self.result != result { self.result = result }
        if result.isReady { CommunityPushRouter.shared.registerIfNeeded() }
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
                self?.apply(result)
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

    var body: some View {
        if availability.result?.isReady == true {
            AppwinCommunityRootView()
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
