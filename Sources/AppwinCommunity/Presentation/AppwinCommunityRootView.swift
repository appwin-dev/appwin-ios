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
        // The cache is hydrated before the first render: without that, an
        // already-known config would flash the default theme.
        let session = Factory.makeSession()
        session.loadCache()
        _session = StateObject(wrappedValue: session)
        _feed = StateObject(wrappedValue: Factory.makeFeedStore())
        self.showsCloseButton = showsCloseButton
        self.onClose = onClose
    }

    var body: some View {
        FeedView(showsCloseButton: showsCloseButton, onClose: onClose)
            .environmentObject(session)
            .environmentObject(feed)
            .communityTheme(CommunityTheme(config: session.config))
            .preferredColorScheme(session.config.theme.colorScheme.preferred)
            .task {
                await session.bootstrap()
                // `bootstrap` already serves the config; this conditional
                // refresh costs only a 304 and keeps the disk cache current.
                await session.refreshConfig()
            }
    }
}
