import Foundation
import AppwinCore

/// Appwin Notifications SDK: push token, in-app messages, automation events.
@MainActor
public enum AppwinNotifications {
  /// Prepares Notifications for this app, and says whether it may be used.
  ///
  /// Call it after `AppwinCore.configure(projectAppId:)` and before asking the
  /// system for push permission: a permission prompt for a product the studio
  /// cannot use spends the one "allow" a user grants, and iOS never asks twice.
  ///
  /// ```swift
  /// if await AppwinNotifications.initialize().isReady {
  ///     await requestPushAuthorization()
  /// }
  /// ```
  ///
  /// Idempotent, and cheap after the first call: the three products share one
  /// server round trip and its cached verdict.
  @discardableResult
  public static func initialize() async -> AppwinInitResult {
    let result = await AppwinCore.availability(of: .notifications)
    isReady = result.isReady
    if !result.isReady { AppwinCore.reportUnavailable(.notifications, result) }
    return result
  }

  /// Whether `initialize()` has returned `.ready`.
  ///
  /// Not enforced on `registerPushToken`: Support sends its own conversation
  /// pushes through the Support route, and a Support-only studio must keep
  /// receiving those without the Notifications product (see the note on
  /// `AppwinSupport.registerPushToken`).
  public private(set) static var isReady = false

  /// Registers the push token (APNs/FCM) with the server.
  ///
  /// `pushOptIn` reflects the user's consent. Set it to `false` rather than
  /// stopping registration: that distinguishes "declined" from "never asked".
  /// It has a default value, so existing calls stay valid.
  public static func registerPushToken(
    _ token: String,
    platform: String = "ios",
    pushOptIn: Bool = true
  ) async throws {
    guard let client = AppwinCore.client else {
      throw AppwinNotificationsError.notConfigured
    }
    struct Body: Encodable {
      let token: String
      let platform: String
      let pushOptIn: Bool
    }
    struct Response: Decodable { let ok: Bool }
    _ = try await client.request(
      path: "/api/sdk/notifications/v1/push-token",
      httpMethod: .post,
      body: Body(token: token, platform: platform, pushOptIn: pushOptIn)
    ) as Response
  }

  /// Fetches the in-app messages pending for this device.
  public static func fetchPendingMessages() async throws -> [InAppMessage] {
    guard let client = AppwinCore.client else {
      throw AppwinNotificationsError.notConfigured
    }
    return try await client.request(
      path: "/api/sdk/notifications/v1/messages",
      httpMethod: .get
    )
  }

  /// Tracks a message being opened, clicked or dismissed.
  public static func track(deliveryId: String, event: TrackEvent) async throws {
    guard let client = AppwinCore.client else {
      throw AppwinNotificationsError.notConfigured
    }
    struct Body: Encodable {
      let deliveryId: String
      let event: String
    }
    try await client.requestVoid(
      path: "/api/sdk/notifications/v1/track",
      httpMethod: .post,
      body: Body(deliveryId: deliveryId, event: event.rawValue)
    )
  }

  /// Sends an SDK event to trigger automations.
  public static func trackEvent(_ event: AutomationEvent, eventName: String? = nil) async throws {
    guard let client = AppwinCore.client else {
      throw AppwinNotificationsError.notConfigured
    }
    struct Body: Encodable {
      let event: String
      let eventName: String?
    }
    struct Response: Decodable { let ok: Bool }
    _ = try await client.request(
      path: "/api/sdk/notifications/v1/events",
      httpMethod: .post,
      body: Body(event: event.rawValue, eventName: eventName)
    ) as Response
  }

  /// Tracks `app_open`, then fetches the pending in-app messages.
  public static func syncOnAppOpen() async throws -> [InAppMessage] {
    try await trackEvent(.appOpen)
    return try await fetchPendingMessages()
  }
}

public struct InAppMessage: Decodable, Sendable {
  public let id: String
  public let campaignId: String
  public let deliveryId: String
  public let channel: String
  public let content: InAppContent
  public let format: String
}

public struct InAppContent: Decodable, Sendable {
  public let title: String?
  public let body: String?
  public let imageUrl: String?
  public let deeplink: String?
}

public enum TrackEvent: String, Sendable {
  case opened, clicked, dismissed
}

public enum AutomationEvent: String, Sendable {
  case appOpen = "app_open"
  case appBackground = "app_background"
  case purchase
  case customEvent = "custom_event"
  case pushOptIn = "push_opt_in"
  case sessionStart = "session_start"
}

public enum AppwinNotificationsError: Error {
  case notConfigured
}
