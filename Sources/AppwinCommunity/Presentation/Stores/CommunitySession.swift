import Foundation

/// Shared state of the first screen: config, groups, profile, badge.
///
/// Hydrated by `bootstrap()`, which returns everything in one round trip: the
/// feed often opens on a cold tab, and three sequential requests would stack
/// three spinners.
///
/// The disk cache serves the anti-flash: on the next launch the known config is
/// applied before the first render, then refreshed in the background.
@MainActor
final class CommunitySession: ObservableObject {
    @Published private(set) var config: CommunityConfig = .defaults
    @Published private(set) var groups: [CommunityGroup] = []
    @Published private(set) var profile: CommunityProfile = .placeholder
    @Published private(set) var unreadNotificationCount: Int = 0

    /// `nil` until the first bootstrap answers, which distinguishes "loading"
    /// from "empty community".
    @Published private(set) var isReady = false
    @Published private(set) var loadError: String?

    /// Selected group. `nil` means the global feed, all groups together.
    @Published var selectedGroupId: String?

    private let repo: CommunityRepository
    private let appId: String

    init(repo: CommunityRepository, appId: String) {
        self.repo = repo
        self.appId = appId
    }

    /// Hydrates from the disk cache, before the first render.
    ///
    /// A cached `enabled: false` is ignored: that value is also the in-memory
    /// default, and applying it would make a failed/offline bootstrap look like
    /// the studio intentionally closed the community.
    func loadCache() {
        guard let data = CommunityConfigCache.read(appId: appId),
              let dto = try? JSONDecoder().decode(CommunityConfigDTO.self, from: data)
        else { return }
        let cached = dto.toDomain()
        guard cached.features.enabled else { return }
        config = cached
    }

    /// Loads, or reloads, the whole startup state.
    func bootstrap() async {
        do {
            let result = try await repo.bootstrap()
            config = result.config
            groups = result.groups
            profile = result.profile
            unreadNotificationCount = result.unreadNotificationCount
            loadError = nil
            isReady = true
        } catch {
            loadError = String(describing: error)
            // Stay `isReady` when a previous bootstrap succeeded: a transient
            // network error must not empty a feed already on screen.
        }
    }

    /// Refreshes the config alone, by ETag. Silent on failure.
    func refreshConfig() async {
        do {
            guard let result = try await repo.fetchConfig(cachedVersion: config.version) else {
                return   // 304, cache toujours valide
            }
            config = result.config
            CommunityConfigCache.write(result.raw, appId: appId)
        } catch {
            // Offline or transient error: keep the current state.
        }
    }

    func setSelectedGroup(_ groupId: String?) {
        selectedGroupId = groupId
    }

    func applyProfile(_ updated: CommunityProfile) {
        profile = updated
    }

    func markNotificationsSeen() {
        unreadNotificationCount = 0
    }

    /// Current group, `nil` on the global feed.
    var selectedGroup: CommunityGroup? {
        guard let selectedGroupId else { return nil }
        return groups.first { $0.id == selectedGroupId }
    }

    /// Can the member post in the current context?
    ///
    /// On the global feed this falls back to "at least one group allows it";
    /// the composer then asks which one to post in.
    var canPost: Bool {
        guard config.features.enabled, config.features.postsEnabled, !profile.isBanned else {
            return false
        }
        if let selectedGroup { return selectedGroup.canPost }
        return groups.contains { $0.canPost }
    }
}
