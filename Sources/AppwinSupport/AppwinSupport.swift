// AppwinSupport - native iOS SDK (ADR-0019).
//
// Intercom model: the whole UI lives here, natively. The Flutter wrapper only
// triggers `AppwinSupport.presentMessenger()`.
//
// Depends on AppwinCore plus Foundation / UIKit / SwiftUI only (ADR-0019 §109).

import Foundation
import UIKit
import SwiftUI
import AppwinCore

@MainActor
public enum AppwinSupport {
  /// Also a sanity check for the Dart-to-Swift bridge.
  public static let version = "0.1.0-dev"

  private(set) static var customer: Customer?

  /// Shared realtime hub (ADR-0028 §9) plus our subscription ids, so closing
  /// the messenger can drop ours without cutting the other product SDKs.
  private static var activeRealtime: RealtimeHub?
  private static var realtimeSubscriptions: [UUID] = []

  // MARK: - Lifecycle

  /// Backwards-compatible entry point; delegates to `AppwinCore.configure`.
  ///
  /// Prefer calling `AppwinCore.configure(projectAppId:)` directly when
  /// integrating several Appwin SDKs: Core owns the device identity, Support
  /// is only a consumer.
  public static func initialize(appId: String) {
    AppwinCore.configure(projectAppId: appId)
  }

  // MARK: - Identification

  /// Anonymous (lead) login. Throws if the network fails or if
  /// `AppwinCore.configure` was never called.
  @discardableResult
  public static func loginUnidentifiedUser() async throws -> Customer {
    guard let client = AppwinCore.client,
          let deviceId = AppwinCore.deviceId, !deviceId.isEmpty else {
      throw AppwinSupportError.notInitialized
    }
    let body = SdkIdentifyRequestSchema(
      email: nil,
      name: "Visitor anonyme \(deviceId)",
      avatarUrl: nil,
      language: nil,
      timezone: nil,
      location: nil,
      plan: nil,
      device: AppwinCore.deviceInfo?.model,
      os: AppwinCore.deviceInfo?.osVersion,
      appVersion: AppwinCore.deviceInfo?.appVersion
    )
    let customer: Customer = try await client.request(
      path: "/api/sdk/support/v1/identify",
      httpMethod: .post,
      body: body
    )
    self.customer = customer
    return customer
  }

  /// In-flight customer init, shared by concurrent callers.
  ///
  /// The messenger mounts several views that may all ask for the customer at
  /// once; without sharing, each would create its own server-side.
  private static var inFlightIdentify: Task<Customer, Error>?

  /// Guarantees a customer record, creating the lead if the host app has not.
  ///
  /// This is what lets `presentMessenger` work after `AppwinCore.configure`
  /// alone. A studio that wants to control when the record is created calls
  /// `loginUnidentifiedUser` or `loginIdentifiedUser` itself, and this becomes
  /// a no-op.
  ///
  /// Intercom model: opening the messenger creates a lead. Without one, the
  /// home screen has nobody to show and cannot use the already-open device
  /// session.
  @discardableResult
  public static func ensureCustomer() async throws -> Customer {
    if let customer { return customer }
    if let inFlight = inFlightIdentify { return try await inFlight.value }

    let task = Task { @MainActor in try await loginUnidentifiedUser() }
    inFlightIdentify = task
    defer { inFlightIdentify = nil }
    return try await task.value
  }

  /// Identified login, promoting lead to user. The `externalId` is propagated
  /// to `AppwinCore` and travels in the `X-Appwin-User-Id` header.
  @discardableResult
  public static func loginIdentifiedUser(externalId: String) async throws -> Customer {
    guard let client = AppwinCore.client else {
      throw AppwinSupportError.notInitialized
    }
    guard !externalId.isEmpty else {
      throw AppwinSupportError.invalidArgument("externalId is empty")
    }
    AppwinCore.identify(externalId: externalId)
    let body = SdkIdentifyRequestSchema(
      email: nil, name: nil, avatarUrl: nil, language: nil, timezone: nil,
      location: nil, plan: nil,
      device: AppwinCore.deviceInfo?.model,
      os: AppwinCore.deviceInfo?.osVersion,
      appVersion: AppwinCore.deviceInfo?.appVersion
    )
    let customer: Customer = try await client.request(
      path: "/api/sdk/support/v1/identify",
      httpMethod: .post,
      body: body
    )
    self.customer = customer
    return customer
  }

  /// Updates the current customer's attributes, Intercom-style. Does **not**
  /// change identity: it keeps the current externalId, or enriches the lead.
  @discardableResult
  public static func updateUser(attributes: AppwinSupportUserAttributes) async throws -> Customer {
    guard let client = AppwinCore.client else {
      throw AppwinSupportError.notInitialized
    }
    let body = SdkIdentifyRequestSchema(
      email: attributes.email,
      name: attributes.name,
      avatarUrl: attributes.avatarUrl,
      language: attributes.language,
      timezone: attributes.timezone,
      location: attributes.location,
      plan: nil,
      device: AppwinCore.deviceInfo?.model,
      os: AppwinCore.deviceInfo?.osVersion,
      appVersion: AppwinCore.deviceInfo?.appVersion
    )
    let customer: Customer = try await client.request(
      path: "/api/sdk/support/v1/identify",
      httpMethod: .post,
      body: body
    )
    self.customer = customer
    return customer
  }

  /// Registers this device's push token. Call again on every token rotation.
  ///
  /// Set `pushOptIn` to `false` rather than stopping registration: that
  /// distinguishes "declined" from "never asked".
  ///
  /// Uses the **Support** route rather than the Notifications one: it writes to
  /// the same table without requiring the Notifications product to be enabled
  /// on the app id, so a Support-only studio still gets conversation pushes.
  public static func registerPushToken(
    _ token: String,
    platform: String = "ios",
    pushOptIn: Bool = true
  ) async throws {
    guard let client = AppwinCore.client else {
      throw AppwinSupportError.notInitialized
    }
    guard !token.isEmpty else {
      throw AppwinSupportError.invalidArgument("token is empty")
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
  }

  struct SdkIdentifyRequestSchema: Codable {
    let email: String?
    let name: String?
    let avatarUrl: String?
    let language: String?
    let timezone: String?
    let location: String?
    let plan: String?
    let device: String?
    let os: String?
    let appVersion: String?
  }

  // MARK: - Presentation

  /// Presents the messenger over the host app, full screen.
  @MainActor
  public static func presentMessenger() {
    guard let presenter = topViewController(), let root = makeMessengerRoot() else { return }
    let host = UIHostingController(rootView: root)
    host.modalPresentationStyle = .fullScreen
    // Without this the UIKit chrome (nav bar, safe area, keyboard) follows the
    // host app's dark mode while the SwiftUI content stays light.
    host.overrideUserInterfaceStyle = .light
    presenter.present(host, animated: true)
  }

  /// The messenger, to embed in the host app's view hierarchy.
  ///
  /// Same screen as `presentMessenger` without the modal presentation or close
  /// button: the app's own container - a tab, a route - is the way out.
  ///
  /// Returns an empty view until `AppwinCore.configure` has run, rather than
  /// crashing on mount.
  @MainActor
  public static func messengerView() -> AnyView {
    makeMessengerRoot() ?? AnyView(EmptyView())
  }

  /// Composition root, shared by both entry points, so the embedded and
  /// presented screens are literally the same. Two parallel constructions would
  /// diverge on the first change, and the bug would only show on one path.
  @MainActor
  private static func makeMessengerRoot() -> AnyView? {
    guard let client = AppwinCore.client else { return nil }

    // Shared stores are created here, once, and handed to the whole tree via
    // the Environment. Views pick them up with @EnvironmentObject; no store is
    // threaded through navigation as a parameter.
    // See docs/sdk-support-ios-state-management.md
    let session           = AppwinSession(customer: self.customer, client: client)
    let conversationStore = Factory.makeConversationStore()
    let messageStore      = Factory.makeMessageStore()
    let composerStore     = Factory.makeComposerStore()
    let faqStore          = Factory.makeFaqStore()
    // Studio-driven config (branding + feature flags), hydrated from cache
    // before the first render to avoid a flash, then refreshed in the
    // background by `AppwinRootView`.
    let configStore       = Factory.makeConfigStore(appId: AppwinCore.projectAppId ?? "")
    configStore.loadCache()

    // Realtime topic `sdk:customer:{id}`, carried by the ephemeral token
    // (ADR-0028). Events trigger a silent REST refetch: payloads are minimal
    // and delivery is at-most-once.
    let realtime = AppwinCore.realtimeHub()
    for id in Self.realtimeSubscriptions { Self.activeRealtime?.off(id) }
    Self.realtimeSubscriptions = []
    Self.activeRealtime = realtime

    let resync: @Sendable () -> Void = {
      Task { @MainActor in
        await messageStore.refreshSilently()
        await conversationStore.refreshSilently()
      }
    }

    var subs: [UUID] = []
    if let realtime {
      subs.append(realtime.on(event: "support.message.created") { _ in resync() })
      subs.append(realtime.on(event: "support.message.updated") { _ in resync() })
      subs.append(realtime.on(event: "support.message.deleted") { raw in
        // Parse before hopping to the MainActor: `Any?` is not Sendable.
        let deletedId = Self.resourceId(from: raw)
        Task { @MainActor in
          if let deletedId {
            messageStore.removeLocalMessage(id: deletedId)
          }
          await conversationStore.refreshSilently()
        }
      })
      subs.append(realtime.on(event: "support.conversation.updated") { _ in
        Task { @MainActor in await conversationStore.refreshSilently() }
      })
      subs.append(realtime.on(event: "support.conversation.created") { _ in
        Task { @MainActor in await conversationStore.refreshSilently() }
      })
      subs.append(realtime.on(event: "support.typing") { raw in
        guard let payload = Self.typingPayload(from: raw),
              payload.typingActor == "agent" else { return }
        let conversationId = payload.conversationId
        let isTyping = payload.isTyping
        Task { @MainActor in
          messageStore.applyPeerTyping(
            conversationId: conversationId,
            isTyping: isTyping
          )
        }
      })
      subs.append(realtime.onConnected(resync))
      realtime.start()
    }
    Self.realtimeSubscriptions = subs

    let root = AppwinRootView(configStore: configStore) {
      HomeView()
        .environmentObject(session)
        .environmentObject(conversationStore)
        .environmentObject(messageStore)
        .environmentObject(composerStore)
        .environmentObject(faqStore)
        .environmentObject(configStore)
        .onDisappear {
          // Drop our handlers but leave the hub running: the connection is
          // shared with the other active product SDKs.
          for id in Self.realtimeSubscriptions { Self.activeRealtime?.off(id) }
          Self.realtimeSubscriptions = []
          Self.activeRealtime = nil
        }
    }
    return AnyView(root)
  }

  /// Topmost view controller, to present over.
  @MainActor
  private static func topViewController() -> UIViewController? {
    let scene = UIApplication.shared.connectedScenes
      .compactMap { $0 as? UIWindowScene }
      .first { $0.activationState == .foregroundActive }
    guard var top = scene?.windows.first(where: \.isKeyWindow)?.rootViewController else {
      return nil
    }
    while let presented = top.presentedViewController {
      top = presented
    }
    return top
  }

  /// Parses the `support.typing` payload. Still tolerates the legacy
  /// Socket.IO array wrapping.
  nonisolated private static func typingPayload(from raw: Any?) -> (
    conversationId: String?,
    isTyping: Bool,
    typingActor: String?
  )? {
    guard let dict = socketDict(from: raw) else { return nil }
    return (
      conversationId: dict["conversationId"] as? String ?? dict["resourceId"] as? String,
      isTyping: dict["isTyping"] as? Bool ?? false,
      typingActor: dict["typingActor"] as? String
    )
  }

  nonisolated private static func resourceId(from raw: Any?) -> String? {
    socketDict(from: raw)?["resourceId"] as? String
  }

  nonisolated private static func socketDict(from raw: Any?) -> [String: Any]? {
    if let arr = raw as? [Any], let first = arr.first as? [String: Any] {
      return first
    }
    return raw as? [String: Any]
  }

  private struct TypingBody: Encodable {
    let isTyping: Bool
  }

  /// Customer typing, sent to agents over HTTP: the gateway takes no
  /// application writes on the socket (ADR-0028). Fire-and-forget, because a
  /// dropped typing event never matters.
  @MainActor
  static func emitTyping(conversationId: String?, isTyping: Bool) {
    guard let conversationId, !conversationId.isEmpty,
          let client = AppwinCore.client else { return }
    Task {
      try? await client.requestVoid(
        path: "/api/sdk/support/v1/conversations/\(conversationId)/typing",
        httpMethod: .post,
        body: TypingBody(isTyping: isTyping)
      )
    }
  }
}
