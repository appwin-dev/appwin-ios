import SwiftUI

/// Root of the SDK's SwiftUI tree.
///
/// Composes the shared stores here, once, and provides them to the whole tree
/// through the Environment - no view receives one as a parameter across
/// la navigation.
///
/// The theme derives from the observed config: when the studio changes its
/// accent colour, this re-render propagates it to the whole screen.
struct AppwinCommunityRootView: View {
    @StateObject private var session: CommunitySession
    @StateObject private var feed: FeedStore

    private let showsCloseButton: Bool
    private let onClose: (() -> Void)?

    init(showsCloseButton: Bool = false, onClose: (() -> Void)? = nil) {
        // Shared stores come back already hydrated (disk cache on first use,
        // live state after): a remount must not flash the default theme.
        let stores = Factory.sharedStores()
        _session = StateObject(wrappedValue: stores.session)
        _feed = StateObject(wrappedValue: stores.feed)
        self.showsCloseButton = showsCloseButton
        self.onClose = onClose
    }

    var body: some View {
        FeedView(showsCloseButton: showsCloseButton, onClose: onClose)
            .environmentObject(session)
            .environmentObject(feed)
            .communityThemed(config: session.config)
            .task {
                await session.bootstrap()
            }
            // Hosts often call `AppwinCore.identify` after the first UI
            // bootstrap; without this pulse the header avatar stays on the
            // anonymous profile.
            .onReceive(NotificationCenter.default.publisher(for: .appwinCommunityUiRefresh)) { _ in
                Task {
                    await session.bootstrap()
                    await feed.refresh()
                }
            }
    }
}

extension Notification.Name {
    /// Posted on an identity change so any mounted root re-bootstraps.
    static let appwinCommunityUiRefresh = Notification.Name("io.appwin.community.uiRefresh")

    /// Posted after the member saved their profile; `object` is the `CommunityProfile`.
    static let appwinCommunityOwnProfileChanged = Notification.Name("io.appwin.community.ownProfileChanged")
}
