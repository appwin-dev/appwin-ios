import Foundation

/// Shared foundation for every Appwin product SDK (Support, Community, …).
///
/// Firebase-style: the host app calls `configure(projectAppId:)` once at
/// launch, then the products read `AppwinCore.client` and `AppwinCore.deviceId`.
@MainActor
public enum AppwinCore {
  public static let version = "0.6.2"

  // MARK: - Public state

  public static private(set) var baseUrl: String = "https://api.appwin.io"

  // appId / deviceId / externalId live outside the MainActor (see IdentityStore)
  // because the networking layer reads them synchronously off the main thread.
  // Read-only here; mutate through `configure` / `identify` / `clearIdentity`.

  /// Public project app id, one per studio project, shared across products.
  public nonisolated static var projectAppId: String? { IdentityStore.read { $0.projectAppId } }

  /// Stable device id, persisted in the keychain so it survives a reinstall.
  public nonisolated static var deviceId: String? { IdentityStore.read { $0.deviceId } }

  /// External user id supplied by the host app. `nil` until the user is
  /// identified, which means anonymous/lead mode.
  public nonisolated static var externalId: String? { IdentityStore.read { $0.externalId } }

  /// Device metadata, captured during `configure`.
  public static private(set) var deviceInfo: DeviceInfo?

  /// Canonical HTTP client. Products take it from here rather than building
  /// their own, so identity headers stay consistent.
  public static private(set) var client: ClientApi?

  /// Base URL of the realtime service. A **separate** service from the API
  /// (see ADR-0028), hence its own override.
  public static private(set) var realtimeBaseUrl: String = "https://ws.appwin.io"

  private static var _realtimeHub: RealtimeHub?
  private static var _availability: AvailabilityStore?
  private static var pushTokenRegistered = false

  /// Whether `registerPushToken` has succeeded at least once this process.
  public static var hasRegisteredPushToken: Bool { pushTokenRegistered }

  // MARK: - Lifecycle

  /// Call once at launch, before using any product SDK. Idempotent.
  ///
  /// Synchronous and 100% local on purpose: it prepares device id, client
  /// and cached token immediately and touches neither the network nor the
  /// server. The session is opened lazily by the first call that needs a
  /// bearer; to force or await it, use `bootstrapSession(externalId:)`.
  public static func configure(
    projectAppId: String,
    baseUrl: String? = nil,
    realtimeBaseUrl: String? = nil
  ) {
    IdentityStore.mutate { $0.projectAppId = projectAppId }
    if let baseUrl { self.baseUrl = baseUrl }
    if let realtimeBaseUrl { self.realtimeBaseUrl = realtimeBaseUrl }

    let key = deviceIdKey
    let deviceId: String
    if let saved = KeychainStore.get(key) {
      deviceId = saved
    } else {
      deviceId = UUID().uuidString
      KeychainStore.set(deviceId, forKey: key)
    }
    IdentityStore.mutate { $0.deviceId = deviceId }
    self.deviceInfo = DeviceInfo.current()
    // Keyed by appId: two apps on the same device must not read each
    // other's verdict.
    self._availability = AvailabilityStore(appId: projectAppId)

    // TEMPORARY (remove once the 401 retry lands). We drop the token instead of
    // preloading it: a bearer minted against a pre-rebuild database (ADR-0025)
    // is dead, and the keychain survives reinstalls, so the dead token came
    // back on every launch. Early calls fall back to the legacy header path
    // until the bootstrap below mints a fresh bearer.
    AuthSession.clearLocal()

    // Headers are resolved per request so they stay current when the token is
    // refreshed or `identify(...)` changes `externalId`. `canonicalHeaders()`
    // is nonisolated and reads the thread-safe IdentityStore, so the @Sendable
    // closure can call it straight from the networking thread.
    self.client = ClientApi(
      baseUrl: self.baseUrl,
      headersProvider: { Self.canonicalHeaders() }
    )

    // Nothing else: configure is 100% local (no network, no server row).
    // Every product - analytics included - starts through its own
    // `initialize()`, and the session is minted lazily by the first call
    // that needs a bearer (`availability` and the event pipeline both know
    // how to wait on `bootstrapSession`).
  }

  // MARK: - Product availability

  /// Whether this app may open `product`, as the server sees it.
  ///
  /// Called by each product's `initialize()`; a host app has no reason to call
  /// it directly. One shared request answers for all three products, and the
  /// verdict is cached on disk so a launch without network falls back to the
  /// last known answer rather than locking a paying studio out.
  public static func availability(of product: AppwinProduct) async -> AppwinInitResult {
    guard let client, let store = _availability else { return .notConfigured }

    // Wait for the session first. `configure` returns before the bearer exists
    // - deliberately, so an offline app still starts fast - and this endpoint
    // is bearer-only. Called straight after `configure`, which is exactly what
    // the documented sequence tells a studio to do, the request would 401 and
    // report `unknown`: "offline on a first launch" for an app that is online.
    //
    // Idempotent and shared between concurrent callers, so the three products
    // initialising at once still cost one round trip.
    _ = try? await bootstrapSession()

    return await store.status(for: product, client: client)
  }

  /// Logs a refused product once, loudly in debug and quietly in release.
  ///
  /// The asymmetry is the point: in development the integrator must trip over
  /// it immediately, in production a paying user must not see a crash because
  /// a plan lapsed. Silence in both would produce the worst bug of the family,
  /// a button that does nothing and that nobody can report.
  public static func reportUnavailable(_ product: AppwinProduct, _ result: AppwinInitResult) {
    let detail: String
    switch result {
    case .ready: return
    case .notConfigured:
      detail = "AppwinCore.configure(projectAppId:) has not been called."
    case .unknown:
      // Deliberately does not say "offline". A 404 from an API older than this
      // SDK lands here too, and telling a developer their online app is offline
      // sends them looking in the wrong place - it cost us an afternoon.
      detail = "the server did not answer. Check the base URL, and that the API "
        + "is recent enough to serve /sdk/v1/availability."
    case .unavailable(.plan):
      detail = "the organisation's plan does not include it."
    case .unavailable(.disabled):
      detail = "it is switched off for this project in the dashboard."
    }
    let message = "[Appwin] \(product.rawValue) is not available: \(detail) "
      + "Gate your own UI on the result of \(product.rawValue).initialize()."
    #if DEBUG
    print(message)
    #else
    NSLog("%@", message)
    #endif
  }

  /// Reminds integrators to register the push token through `registerPushToken`.
  ///
  /// Optional for Support and Community, required for Notifications. A missing
  /// token does not block initialization: we log loudly in debug so the
  /// omission shows up during integration, not in production silence.
  ///
  /// Deferred a few seconds: Flutter/Firebase apps typically call
  /// `registerPushToken` after `initialize()` (once FCM/APNs is ready). Warn
  /// only if the token is still missing after that window.
  public static func reportMissingPushToken(for product: AppwinProduct) {
    Task { @MainActor in
      try? await Task.sleep(nanoseconds: 3_000_000_000)
      guard !pushTokenRegistered else { return }
      let requirement = product == .notifications ? "required" : "strongly recommended"
      let message =
        "[Appwin] Push token not registered yet (\(requirement) for \(product.rawValue)). "
        + "Call AppwinCore.registerPushToken(...) after configure, and again on "
        + "every FCM/APNs token rotation."
      #if DEBUG
      print(message)
      #else
      NSLog("%@", message)
      #endif
    }
  }

  /// Registers this device's push token with Appwin. Call again on every token
  /// rotation.
  ///
  /// Uses the Support route so the same table is updated without requiring the
  /// Notifications product to be enabled. Shared by Support, Community and
  /// Notifications.
  ///
  /// Set `pushOptIn` to `false` rather than stopping registration: that
  /// distinguishes "declined" from "never asked".
  public static func registerPushToken(
    _ token: String,
    platform: String = "ios",
    pushOptIn: Bool = true
  ) async throws {
    guard let client = client else {
      throw AppwinApiError.notConfigured
    }
    guard !token.isEmpty else {
      throw AppwinApiError.encodingFailed(
        NSError(
          domain: "AppwinCore",
          code: 0,
          userInfo: [NSLocalizedDescriptionKey: "token must not be blank"]
        )
      )
    }
    struct Body: Encodable {
      let token: String
      let platform: String
      let pushOptIn: Bool
    }
    struct Response: Decodable { let ok: Bool }
    _ = try await client.request(
      path: "/api/sdk/support/v1/push-token",
      httpMethod: .post,
      body: Body(token: token, platform: platform, pushOptIn: pushOptIn)
    ) as Response
    pushTokenRegistered = true
  }

  /// Shared realtime hub (ADR-0028 §9): one multiplexed WebSocket for the whole
  /// app, across every product SDK. Created on first access, `nil` until
  /// `configure(...)` has run.
  ///
  /// The ephemeral token is minted per (re)connection with the session bearer,
  /// so the hub waits on `bootstrapSession()` implicitly: without a bearer the
  /// mint fails and the backoff retries.
  public static func realtimeHub() -> RealtimeHub? {
    if let hub = _realtimeHub { return hub }
    guard let client else { return nil }
    var ws = realtimeBaseUrl
      .replacingOccurrences(of: "https://", with: "wss://")
      .replacingOccurrences(of: "http://", with: "ws://")
    if !ws.hasSuffix("/ws") { ws += "/ws" }
    guard let url = URL(string: ws) else { return nil }
    let hub = RealtimeHub.make(gatewayUrl: url, api: client)
    _realtimeHub = hub
    return hub
  }

  /// In-flight init, shared by concurrent callers.
  ///
  /// `/sdk/v1/auth/init` rotates the token: the server keeps a single
  /// `customer_sessions` row per (sdkApp, device), so a second init revokes the
  /// first. Two simultaneous calls - the task spawned by `configure` and a
  /// plugin's explicit await - used to race, and whichever answer landed last
  /// won on the client, sometimes carrying the already-revoked token. That was
  /// the intermittent "Invalid or revoked token" at boot.
  private static var inFlightBootstrap: Task<String, Error>?

  /// Creates (or rotates) the server session and persists the token. Called in
  /// the background by `configure(...)`; await it explicitly before a call that
  /// requires a bearer. Idempotent.
  @discardableResult
  public static func bootstrapSession(externalId: String? = nil) async throws -> String {
    // No `await` between this check and the assignment below: we are on the
    // MainActor, so the section is atomic.
    if let inFlight = inFlightBootstrap {
      return try await inFlight.value
    }
    guard let appId = projectAppId, let deviceId = deviceId else {
      throw AppwinApiError.invalidUrl // stands in for "configure was not called"
    }
    let task = Task { @MainActor in
      try await AuthSession.bootstrap(
        baseUrl: baseUrl,
        appId: appId,
        deviceId: deviceId,
        externalId: externalId,
        deviceInfo: deviceInfo
      )
    }
    inFlightBootstrap = task
    defer { inFlightBootstrap = nil }
    return try await task.value
  }

  /// Promotes the device identity to an identified user, Intercom-style. The
  /// identity is shared by every active product SDK.
  public static func identify(externalId: String) {
    IdentityStore.mutate { $0.externalId = externalId }
  }

  /// Forgets the identity locally, without revoking the session server-side.
  /// For a real logout, use `signOut()`.
  public static func clearIdentity() {
    IdentityStore.mutate { $0.externalId = nil }
  }

  private static let deviceIdKey = "appwin.core.deviceId"

  /// Drops the keychain device id and bearer **before** `configure` (or after a
  /// reinstall that kept Keychain items). Call this when you need a brand-new
  /// anonymous user: uninstall alone is not enough on iOS.
  public static func wipeStoredDeviceIdentity() {
    KeychainStore.delete(deviceIdKey)
    AuthSession.clearLocal()
    IdentityStore.mutate {
      $0.deviceId = nil
      $0.externalId = nil
      $0.bearerToken = nil
      $0.sessionId = nil
    }
  }

  /// Mints a new anonymous device id after wiping the previous one.
  ///
  /// Use from a debug / sandbox "start over" action. Prefer
  /// `wipeStoredDeviceIdentity()` *before* `configure` on a cold launch.
  public static func resetDeviceIdentity() {
    wipeStoredDeviceIdentity()
    let deviceId = UUID().uuidString
    KeychainStore.set(deviceId, forKey: deviceIdKey)
    IdentityStore.mutate {
      $0.deviceId = deviceId
      $0.externalId = nil
    }
  }

  /// Revokes the session server-side, clears the keychain and resets the local
  /// identity. Tolerant of network failures: the local token is dropped even if
  /// the revoke call fails.
  public static func signOut() async {
    await AuthSession.signOut(baseUrl: baseUrl)
    IdentityStore.mutate { $0.externalId = nil }
  }

  // MARK: - Internals (visible to product SDKs)

  /// Headers added to every request from the canonical client. Public so a
  /// product can reuse them for an endpoint that bypasses `client` (a presigned
  /// S3 upload, for instance).
  ///
  /// The legacy `X-Appwin-*` headers are still sent alongside the bearer while
  /// the backend migration is in flight: `SupportSdkGuard` accepts both.
  public nonisolated static func canonicalHeaders() -> [String: String] {
    var h: [String: String] = [
      "Content-Type": "application/json",
      "X-Appwin-Platform": "ios",
    ]
    let identity = IdentityStore.read { $0 }
    if let appId = identity.projectAppId { h["X-Appwin-App-Id"] = appId }
    if let deviceId = identity.deviceId { h["X-Appwin-Device-Id"] = deviceId }
    if let externalId = identity.externalId { h["X-Appwin-User-Id"] = externalId }
    if let token = AuthSession.currentToken() {
      h["Authorization"] = "Bearer \(token)"
    }
    return h
  }
}
