// Messenger config retrieval contract. The Infra implementation handles the
// ETag and the 304.
import Foundation

/// One fetch's result: the parsed config plus the raw body, for the local cache.
struct ConfigFetchResult {
    let config: MessengerConfig
    let raw: Data
}

protocol ConfigRepository: Sendable {
    /// Fetches the config. `cachedVersion` goes out as `If-None-Match`, and a
    /// `304` returns `nil`, meaning the local cache is still valid.
    func fetch(cachedVersion: Int?) async throws -> ConfigFetchResult?
}
