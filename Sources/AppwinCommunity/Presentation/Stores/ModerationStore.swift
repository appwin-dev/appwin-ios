import Foundation

/// The moderation queue of moderators and admins (Figma 182:857), in two tabs
/// as on the dashboard: « À traiter » and « Traités ».
@MainActor
final class ModerationStore: ObservableObject {
    @Published private(set) var tab: ModerationQueueTab = .pending
    @Published private(set) var items: [ModerationQueueItem] = []
    @Published private(set) var pendingCount = 0
    @Published private(set) var isLoading = false
    @Published private(set) var loadFailed = false
    @Published private(set) var failedItemId: String?
    @Published private(set) var busyItemId: String?

    private var hasMore = false
    private let repo: CommunityModerationRepository
    private let pageSize = 20

    init(repo: CommunityModerationRepository) {
        self.repo = repo
    }

    func select(_ tab: ModerationQueueTab) async {
        guard tab != self.tab else { return }
        self.tab = tab
        items = []
        hasMore = false
        failedItemId = nil
        await load()
    }

    func load() async {
        let tab = self.tab
        isLoading = true
        defer { isLoading = false }
        do {
            let page = try await repo.queue(tab: tab, offset: 0, limit: pageSize)
            // A tab switched while loading: this page belongs to the other one.
            guard tab == self.tab else { return }
            items = page.items
            pendingCount = page.pendingCount
            hasMore = page.hasMore
            loadFailed = false
        } catch {
            guard tab == self.tab else { return }
            loadFailed = items.isEmpty
        }
    }

    func loadMoreIfNeeded(after item: ModerationQueueItem) async {
        guard hasMore, !isLoading, item.id == items.last?.id else { return }
        let tab = self.tab
        isLoading = true
        defer { isLoading = false }
        guard let page = try? await repo.queue(tab: tab, offset: items.count, limit: pageSize),
              tab == self.tab else { return }
        let known = Set(items.map(\.id))
        items += page.items.filter { !known.contains($0.id) }
        pendingCount = page.pendingCount
        hasMore = page.hasMore
    }

    /// « À traiter »: the item leaves the queue once the server has it.
    /// « Traités »: it stays, with its new state and this moderator's name.
    func decide(_ item: ModerationQueueItem, _ action: ModerationAction, actorName: String) async {
        let tab = self.tab
        busyItemId = item.id
        failedItemId = nil
        defer { busyItemId = nil }
        do {
            try await repo.decide(
                targetType: item.targetType,
                targetId: item.targetId,
                action: action,
                reason: nil,
                durationHours: nil,
                // Decided reports are closed already: only open ones are settled.
                reportIds: tab == .pending ? item.reports.map(\.id) : []
            )
            guard tab == self.tab else { return }
            switch tab {
            case .pending:
                items.removeAll { $0.id == item.id }
                pendingCount = max(0, pendingCount - 1)
            case .resolved:
                if let index = items.firstIndex(where: { $0.id == item.id }) {
                    items[index] = item.decided(action, by: actorName)
                }
            }
        } catch {
            failedItemId = item.id
        }
    }
}
