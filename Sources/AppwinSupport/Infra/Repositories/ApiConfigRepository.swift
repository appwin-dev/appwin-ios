import Foundation
import AppwinCore

/// Fetches the messenger config. The scope (org and project) is resolved
/// server-side by `SupportSdkGuard` from the device, so nothing is passed.
/// Sends `If-None-Match` to benefit from the `304`.
final class ApiConfigRepository: ConfigRepository {
    private let clientApi: ClientApi

    init(clientApi: ClientApi) {
        self.clientApi = clientApi
    }

    func fetch(cachedVersion: Int?) async throws -> ConfigFetchResult? {
        var extraHeaders: [String: String] = [:]
        if let v = cachedVersion, v > 0 {
            extraHeaders["If-None-Match"] = String(v)
        }
        let (status, data) = try await clientApi.requestRaw(
            path: "/api/sdk/support/v1/config",
            httpMethod: .get,
            extraHeaders: extraHeaders
        )
        if status == 304 { return nil }   // cache local toujours valide
        let dto = try JSONDecoder().decode(MessengerConfigDTO.self, from: data)
        let config = await MainActor.run { dto.toDomain() }
        return ConfigFetchResult(config: config, raw: data)
    }
}
