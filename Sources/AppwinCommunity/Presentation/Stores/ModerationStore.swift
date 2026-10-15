import Foundation

/// The moderation queue of moderators and admins (Figma 182:857).
@MainActor
final class ModerationStore: ObservableObject {
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

    func load() async {
        isLoading = true
        defer { isLoading = false }
        do {
            let page = try await repo.queue(offset: 0, limit: pageSize)
            items = page.items
            pendingCount = page.pendingCount
            hasMore = page.hasMore
            loadFailed = false
        } catch {
            loadFailed = items.isEmpty
        }
    }

    func loadMoreIfNeeded(after item: ModerationQueueItem) async {
        guard hasMore, !isLoading, item.id == items.last?.id else { return }
        isLoading = true
        defer { isLoading = false }
        guard let page = try? await repo.queue(offset: items.count, limit: pageSize) else { return }
        let known = Set(items.map(\.id))
        items += page.items.filter { !known.contains($0.id) }
        pendingCount = page.pendingCount
        hasMore = page.hasMore
    }

    /// Settles an item: it leaves the queue once the server has it.
    func decide(_ item: ModerationQueueItem, _ action: ModerationAction) async {
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
                reportIds: item.reports.map(\.id)
            )
            items.removeAll { $0.id == item.id }
            pendingCount = max(0, pendingCount - 1)
        } catch {
            failedItemId = item.id
        }
    }
}
