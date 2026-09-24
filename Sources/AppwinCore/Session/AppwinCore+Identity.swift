import Foundation

/// What changed, as told to the product modules through `observeIdentity`.
package enum AppwinIdentityChange: Sendable {
  /// The session now points at another customer (`identify`, `logout`): cached
  /// customer data and realtime topics are stale.
  case session
  /// Same customer, new attributes (`updateUser`, or `identify` with attributes on an
  /// already open session).
  case attributes
}

extension AppwinCore {
  // MARK: - Identity (public host API)

  /// Identifies the person using the app with your own user id.
  ///
  /// The id is persisted on the device, so it survives relaunches: call this
  /// at sign-in, not on every launch. The anonymous history of this device
  /// (conversations, events) is merged into the identified user server-side,
  /// and every product (Support, Community, Notifications, Analytics,
  /// Attribution) switches to that user.
  ///
  /// If opening the session fails, the id stays stored and the next session
  /// bootstrap retries with it.
  ///
  /// - Parameters:
  ///   - externalId: your stable user id. Must not be empty.
  ///   - attributes: optional attributes to record at the same time, see
  ///     `updateUser(_:)`.
  /// - Throws: `AppwinApiError.invalidArgument` for an empty id,
  ///   `AppwinApiError.notConfigured` before `configure`, or the network error.
  public static func identify(externalId: String, attributes: AppwinUserAttributes? = nil) async throws {
    guard !externalId.isEmpty else {
      throw AppwinApiError.invalidArgument("externalId must not be empty")
    }
    guard let client else { throw AppwinApiError.notConfigured }

    let sessionAlreadyIdentified = IdentityStore.read {
      $0.bearerToken != nil && $0.sessionExternalId == externalId
    }
    storeExternalId(externalId)
    if !sessionAlreadyIdentified {
      // `/auth/init` with the externalId is what promotes the device's lead
      // into the user server-side.
      _ = try await bootstrapSession()
    }
    if let attributes {
      try await client.requestVoid(path: "/api/sdk/v1/me", httpMethod: .patch, body: attributes)
    }
    if !sessionAlreadyIdentified {
      notifyIdentityChanged(.session)
    } else if attributes != nil {
      notifyIdentityChanged(.attributes)
    }
  }

  /// Records attributes on the current user, identified or anonymous.
  ///
  /// Only the non-`nil` fields are sent; the others keep their server-side
  /// value. Does not change who the user is: use `identify` for that.
  ///
  /// - Throws: `AppwinApiError.notConfigured` before `configure`, or the
  ///   network error.
  public static func updateUser(_ attributes: AppwinUserAttributes) async throws {
    guard let client else { throw AppwinApiError.notConfigured }
    if AuthSession.currentToken() == nil {
      _ = try await bootstrapSession()
    }
    try await client.requestVoid(path: "/api/sdk/v1/me", httpMethod: .patch, body: attributes)
    notifyIdentityChanged(.attributes)
  }

  /// Signs the user out and continues as a new anonymous visitor.
  ///
  /// Revokes the session server-side, forgets the stored externalId and opens
  /// a fresh anonymous session. A push token registered earlier is registered
  /// again on the new session, since the revoke drops it server-side. Never
  /// throws: a revoke that fails offline still leaves the device signed out
  /// locally.
  public static func logout() async {
    // A bootstrap still in flight for the outgoing user would land after the
    // revoke and re-attach the device to them.
    if let inFlight = inFlightBootstrap {
      _ = try? await inFlight.task.value
    }
    await AuthSession.revoke(baseUrl: baseUrl)
    storeExternalId(nil)
    _ = try? await bootstrapSession()
    if let push = lastPushRegistration {
      try? await registerPushToken(push.token, platform: push.platform, pushOptIn: push.pushOptIn)
    }
    notifyIdentityChanged(.session)
  }

  // MARK: - Session bootstrap (product modules only)

  private struct InFlightBootstrap {
    let id: UUID
    let externalId: String?
    let task: Task<String, Error>
  }

  /// In-flight init, shared by concurrent callers.
  ///
  /// `/sdk/v1/auth/init` rotates the token: the server keeps a single
  /// `customer_sessions` row per (sdkApp, device), so a second init revokes the
  /// first. Two simultaneous calls used to race, and whichever answer landed
  /// last won on the client, sometimes carrying the already-revoked token.
  private static var inFlightBootstrap: InFlightBootstrap?

  /// Creates (or rotates) the server session with the stored externalId and
  /// persists the token. Await it before a call that requires a bearer.
  ///
  /// Always sends the stored externalId: an init without it resets the
  /// session's `external_id` server-side, so a product re-authenticating after
  /// a 401 would silently turn an identified user back into a lead.
  @discardableResult
  package static func bootstrapSession() async throws -> String {
    while true {
      let wanted = externalId
      if let inFlight = inFlightBootstrap {
        if inFlight.externalId == wanted { return try await inFlight.task.value }
        // Started for another identity, typically the anonymous boot racing an
        // `identify`: its token would not carry `wanted`. Let it land (each
        // init rotates the previous one), then mint ours.
        _ = try? await inFlight.task.value
        continue
      }
      guard let appId = projectAppId, let deviceId else {
        throw AppwinApiError.notConfigured
      }
      let id = UUID()
      let info = deviceInfo
      let url = baseUrl
      let task = Task { @MainActor in
        // Cleared inside the task, before its value is delivered, so a caller
        // resuming from it never finds it still registered and loops on it.
        defer { if inFlightBootstrap?.id == id { inFlightBootstrap = nil } }
        return try await AuthSession.bootstrap(
          baseUrl: url,
          appId: appId,
          deviceId: deviceId,
          externalId: wanted,
          deviceInfo: info
        )
      }
      // No `await` since the check above: on the MainActor this is atomic.
      inFlightBootstrap = InFlightBootstrap(id: id, externalId: wanted, task: task)
      return try await task.value
    }
  }

  // MARK: - Identity-changed hook (product modules only)

  private static var identityObservers: [AppwinProduct: @MainActor (AppwinIdentityChange) -> Void] = [:]

  /// Registers `product`'s reaction to an identity change, replacing any
  /// previous one so `initialize()` can call it every time.
  ///
  /// Called synchronously right after the session switched: drop cached state
  /// here and refetch in a `Task`.
  package static func observeIdentity(
    _ product: AppwinProduct,
    _ observer: @escaping @MainActor (AppwinIdentityChange) -> Void
  ) {
    identityObservers[product] = observer
  }

  private static func notifyIdentityChanged(_ change: AppwinIdentityChange) {
    if change == .session {
      realtimeHubIfCreated?.restartIfRunning()
    }
    for observer in identityObservers.values {
      observer(change)
    }
  }

  private static func storeExternalId(_ value: String?) {
    IdentityStore.mutate { $0.externalId = value }
    if let value {
      KeychainStore.set(value, forKey: externalIdKey)
    } else {
      KeychainStore.delete(externalIdKey)
    }
  }
}
