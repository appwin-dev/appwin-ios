import SwiftUI

/// Figma « Modération (N) » (182:857): the queue moderators and admins decide
/// on, and what was already handled, in two tabs as on the dashboard.
struct ModerationView: View {
    @EnvironmentObject private var session: CommunitySession
    @Environment(\.communityTheme) private var theme
    @Environment(\.dismiss) private var dismiss
    @StateObject private var store = ModerationStore(repo: Factory.moderationRepository())
    @State private var reportsItem: ModerationQueueItem?
    @State private var replyItem: ModerationQueueItem?

    var body: some View {
        VStack(spacing: 0) {
            ModerationTabBar(selection: store.tab) { tab in
                Task { await store.select(tab) }
            }
            content
        }
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
        .sheet(item: $replyItem) { item in
            ModerationReplySheet(item: item)
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
                    title: store.loadFailed ? CommunityStrings.loadErrorTitle : emptyTitle,
                    message: store.loadFailed ? CommunityStrings.loadErrorMessage : emptyHint,
                    actionTitle: store.loadFailed ? CommunityStrings.retry : nil,
                    expandsToFill: true,
                    action: store.loadFailed ? { Task { await store.load() } } : nil
                )
            }
        } else {
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 24) {
                    if store.tab == .pending {
                        CommunityInfoBox(markdown: CommunityStrings.moderationInfo)
                    }
                    ForEach(store.items) { item in
                        ModerationQueueCard(
                            item: item,
                            isResolved: store.tab == .resolved,
                            isBusy: store.busyItemId == item.id,
                            failed: store.failedItemId == item.id,
                            onDecide: { action in
                                Task { await store.decide(item, action, actorName: session.profile.nickname) }
                            },
                            onShowReports: { reportsItem = item },
                            onReply: canReply(to: item) ? { replyItem = item } : nil
                        )
                        .task { await store.loadMoreIfNeeded(after: item) }
                    }
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 8)
            }
        }
    }

    private var emptyTitle: String {
        store.tab == .pending ? CommunityStrings.moderationEmpty : CommunityStrings.moderationResolvedEmpty
    }

    private var emptyHint: String {
        store.tab == .pending ? CommunityStrings.moderationEmptyHint : CommunityStrings.moderationResolvedEmptyHint
    }

    /// The reply is a comment its author reads under their post, hidden or not;
    /// a deleted content has no thread anyone would read it in.
    private func canReply(to item: ModerationQueueItem) -> Bool {
        guard session.config.features.commentsEnabled else { return false }
        guard item.status != .removed, !item.post.isRemoved else { return false }
        return (item.comment?.author ?? item.post.author) != nil
    }
}

/// « À traiter » / « Traités »: the group pills of the feed, for two fixed tabs.
private struct ModerationTabBar: View {
    let selection: ModerationQueueTab
    let onSelect: (ModerationQueueTab) -> Void

    @Environment(\.communityTheme) private var theme

    var body: some View {
        HStack(spacing: 6) {
            ForEach(ModerationQueueTab.allCases, id: \.self) { tab in
                pill(tab)
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
    }

    private func pill(_ tab: ModerationQueueTab) -> some View {
        let isActive = tab == selection
        let shape = RoundedRectangle(cornerRadius: theme.radius.card)
        return Button { onSelect(tab) } label: {
            Text(tab == .pending ? CommunityStrings.moderationTabPending : CommunityStrings.moderationTabResolved)
                .font(theme.font(14, weight: isActive ? .semibold : .medium))
                .foregroundStyle(isActive ? theme.colors.onAccent : theme.colors.textTertiary)
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .background {
                    if isActive {
                        shape.fill(theme.accentFill)
                    } else {
                        shape.strokeBorder(theme.colors.border, lineWidth: 1)
                    }
                }
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(isActive ? .isSelected : [])
    }
}
