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
    private let profileEditing: ProfileEditingHandlers
    @State private var registration = UUID()
    @State private var hostController: UIViewController?

    init(
        showsCloseButton: Bool = false,
        profileEditing: ProfileEditingHandlers = ProfileEditingHandlers(),
        onClose: (() -> Void)? = nil
    ) {
        // Shared stores come back already hydrated (disk cache on first use,
        // live state after): a remount must not flash the default theme.
        let stores = Factory.sharedStores()
        _session = StateObject(wrappedValue: stores.session)
        _feed = StateObject(wrappedValue: stores.feed)
        self.showsCloseButton = showsCloseButton
        self.onClose = onClose
        self.profileEditing = profileEditing
    }

    var body: some View {
        FeedView(showsCloseButton: showsCloseButton, onClose: onClose)
            .environmentObject(session)
            .environmentObject(feed)
            .communityThemed(config: session.config)
            .background(CommunityHostControllerReader { hostController = $0 }.frame(width: 0, height: 0))
            .onAppear(perform: registerProfileEditing)
            .onChange(of: hostController) { _ in registerProfileEditing() }
            .onDisappear { CommunityProfileEditing.unregister(token: registration) }
            .task {
                await session.bootstrap()
                await session.markNotificationsSeen()
            }
            // Again on every return to a feed kept mounted (host tab bar).
            .onAppear {
                Task { await session.markNotificationsSeen() }
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
            // A sanction arrived over realtime: the bell reads its count from
            // the bootstrap, and would otherwise wait for the next one.
            .onReceive(NotificationCenter.default.publisher(for: .appwinCommunitySanctionsChanged)) { _ in
                Task { await session.bootstrap() }
            }
    }
}

extension AppwinCommunityRootView {
    /// Again on each appearance: the feed on screen is the one whose handlers
    /// a tap must reach.
    private func registerProfileEditing() {
        CommunityProfileEditing.register(
            profileEditing,
            token: registration,
            host: hostController,
            isPresented: showsCloseButton
        )
    }
}

extension Notification.Name {
    /// Posted on an identity change so any mounted root re-bootstraps.
    static let appwinCommunityUiRefresh = Notification.Name("io.appwin.community.uiRefresh")

    /// Posted after the member saved their profile; `object` is the `CommunityProfile`.
    static let appwinCommunityOwnProfileChanged = Notification.Name("io.appwin.community.ownProfileChanged")

    /// Posted when a sanction notification (removed content, warning, ban)
    /// arrives, so the mounted feed refreshes its bell.
    static let appwinCommunitySanctionsChanged = Notification.Name("io.appwin.community.sanctionsChanged")
}
