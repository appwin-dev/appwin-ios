import Foundation

/// Holds the current messenger config (branding plus modules) and refreshes it
/// stale-while-revalidate. `AppwinTheme` derives from `config.branding` at the
/// top of the tree; `config.modules` gates features such as the FAQ. One fetch,
/// one cache, one ETag for both branding and flags.
@MainActor
final class ConfigStore: ObservableObject {
    @Published private(set) var config: MessengerConfig = .defaults
    private let repo: ConfigRepository
    private let appId: String

    init(repo: ConfigRepository, appId: String) {
        self.repo = repo
        self.appId = appId
    }

    /// Hydrates from the UserDefaults cache, before the first fetch, so a known
    /// config does not flash the defaults.
    func loadCache() {
        guard let data = ConfigCache.read(appId: appId),
              let dto = try? JSONDecoder().decode(MessengerConfigDTO.self, from: data)
        else { return }
        config = dto.toDomain()
    }

    /// Refreshes from the API. A `304` keeps the cache; a network failure is
    /// silent and keeps the current state.
    func refresh() async {
        do {
            guard let result = try await repo.fetch(cachedVersion: config.version) else {
                return
            }
            config = result.config
            ConfigCache.write(result.raw, appId: appId)
        } catch {
            // Offline or transient error: keep the current state.
        }
    }
}
