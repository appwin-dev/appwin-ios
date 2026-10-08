// AuthSession - SDK bearer token (ADR-0021). Wraps /sdk/v1/auth/init, the
// keychain persistence and the revoke/clear lifecycle.

import Foundation

/// Raw `POST /sdk/v1/auth/init` response.
private struct InitSessionResponse: Decodable {
  let token: String
  let customerSessionId: String
  let expiresAt: String?
}

/// Body sent to `/sdk/v1/auth/init`.
private struct InitSessionBody: Encodable {
  let deviceId: String
  let externalId: String?
  let platform: String?
  let model: String?
  let os: String?
  let appVersion: String?
  /// Device primary language (ISO 639-1). Fill-if-empty on the customer.
  let language: String?
  /// What the dashboard displays as the app's SDK version (Android has
  /// sent it from day one; iOS shipped without it until 0.6.2).
  let sdkVersion: String?
}

@MainActor
public enum AuthSession {
  /// Survives a reinstall (see KeychainStore), so the user keeps their session
  /// as long as the app id does not change.
  nonisolated private static let keychainKey = "appwin.core.bearer.token"

  /// Current session id, returned by /init. Stored alongside the token so both
  /// are updated in one critical section.
  public nonisolated static var currentSessionId: String? { IdentityStore.read { $0.sessionId } }

  /// Current bearer token, `nil` until initialised.
  ///
  /// Lazy: an empty memory cache falls back to the keychain and repopulates
  /// itself. `nonisolated` because `canonicalHeaders()` calls it from the
  /// networking thread; the read-then-write happens under the store's lock.
  public nonisolated static func currentToken() -> String? {
    IdentityStore.lock.withLock { state in
      if let cached = state.bearerToken { return cached }
      if let loaded = KeychainStore.get(keychainKey) {
        state.bearerToken = loaded
        return loaded
      }
      return nil
    }
  }

  /// Forces a reload from the keychain, after an external wipe.
  public nonisolated static func reloadFromKeychain() {
    IdentityStore.mutate { $0.bearerToken = KeychainStore.get(keychainKey) }
  }

  /// Creates or rotates a session and persists the token. Idempotent
  /// server-side: a repeated call on the same `(appId, deviceId)` rotates the
  /// token and invalidates the previous one.
  ///
  /// Not host API: go through `AppwinCore.bootstrapSession()`, which dedupes
  /// concurrent calls and sends the persisted externalId.
  ///
  /// - Throws: `AppwinApiError` when /init fails.
  @discardableResult
  package static func bootstrap(
    baseUrl: String,
    appId: String,
    deviceId: String,
    externalId: String? = nil,
    deviceInfo: DeviceInfo? = nil
  ) async throws -> String {
    // A throwaway client for /init: no bearer, since obtaining one is the
    // point. Only the app id, which identifies the project.
    let bootstrapClient = ClientApi(
      baseUrl: baseUrl,
      headers: [
        "X-Appwin-App-Id": appId,
        "Content-Type": "application/json",
      ]
    )

    let body = InitSessionBody(
      deviceId: deviceId,
      externalId: externalId,
      platform: deviceInfo?.platform,
      model: deviceInfo?.model,
      os: deviceInfo?.osVersion,
      appVersion: deviceInfo?.appVersion,
      language: {
        guard let tag = Locale.preferredLanguages.first else { return nil }
        return Locale(identifier: tag).language.languageCode?.identifier
      }(),
      sdkVersion: AppwinCore.version
    )

    let response: InitSessionResponse = try await bootstrapClient.request(
      path: "/api/sdk/v1/auth/init",
      httpMethod: .post,
      body: body
    )

    // Overwrite any previous session: the server rotated it anyway.
    IdentityStore.mutate {
      $0.bearerToken = response.token
      $0.sessionId = response.customerSessionId
      $0.sessionExternalId = externalId
    }
    KeychainStore.set(response.token, forKey: keychainKey)

    return response.token
  }

  /// Revokes the session server-side and clears the keychain.
  ///
  /// Error-tolerant: if /revoke fails (offline, already revoked) the local
  /// token is dropped anyway. Not being authenticated locally matters more than
  /// server-side tidiness.
  package static func revoke(baseUrl: String) async {
    let token = currentToken()
    if let token {
      let client = ClientApi(
        baseUrl: baseUrl,
        headers: ["Authorization": "Bearer \(token)"]
      )
      // Errors are ignored on purpose: already revoked, network down, …
      _ = try? await client.requestVoid(path: "/api/sdk/v1/auth/revoke", httpMethod: .post)
    }
    IdentityStore.mutate {
      $0.bearerToken = nil
      $0.sessionId = nil
      $0.sessionExternalId = nil
    }
    KeychainStore.delete(keychainKey)
  }

  /// Drops the local token without calling /revoke.
  public static func clearLocal() {
    IdentityStore.mutate {
      $0.bearerToken = nil
      $0.sessionId = nil
      $0.sessionExternalId = nil
    }
    KeychainStore.delete(keychainKey)
  }
}
