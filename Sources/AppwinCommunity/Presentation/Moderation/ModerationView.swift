import SwiftUI

/// Figma « Modération (N) » (182:857): the queue moderators and admins decide on.
struct ModerationView: View {
    @EnvironmentObject private var session: CommunitySession
    @Environment(\.communityTheme) private var theme
    @Environment(\.dismiss) private var dismiss
    @StateObject private var store = ModerationStore(repo: Factory.moderationRepository())
    @State private var reportsItem: ModerationQueueItem?

    var body: some View {
        content
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(theme.colors.background.ignoresSafeArea())
        .navigationTitle(CommunityStrings.moderationTitle(store.pendingCount))
        .navigationBarTitleDisplayMode(.inline)
        .task { await store.load() }
        .refreshable { await store.load() }
        .onChange(of: store.pendingCount) { session.setModerationPendingCount($0) }
        .sheet(item: $reportsItem) { item in
            ReportsListSheet(reports: item.reports, wasAutoHidden: item.status == .pending)
                .environmentObject(session)
        }
    }

    @ViewBuilder
    private var content: some View {
        if store.items.isEmpty {
            if store.isLoading {
                ProgressView().tint(theme.colors.accent).frame(maxHeight: .infinity)
            } else {
                CommunityEmptyState(
                    icon: .shieldStar,
                    title: store.loadFailed ? CommunityStrings.loadErrorTitle : CommunityStrings.moderationEmpty,
                    message: store.loadFailed ? CommunityStrings.loadErrorMessage : CommunityStrings.moderationEmptyHint,
                    actionTitle: store.loadFailed ? CommunityStrings.retry : nil,
                    expandsToFill: true,
                    action: store.loadFailed ? { Task { await store.load() } } : nil
                )
            }
        } else {
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 24) {
                    CommunityInfoBox(markdown: CommunityStrings.moderationInfo)
                    ForEach(store.items) { item in
                        ModerationQueueCard(
                            item: item,
                            isBusy: store.busyItemId == item.id,
                            failed: store.failedItemId == item.id,
                            onDecide: { action in Task { await store.decide(item, action) } },
                            onShowReports: { reportsItem = item }
                        )
                        .task { await store.loadMoreIfNeeded(after: item) }
                    }
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 8)
            }
        }
    }
}
