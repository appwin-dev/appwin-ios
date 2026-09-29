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

  /// Session of the open messenger, so an identity change refreshes it live.
  private static weak var presentedSession: AppwinSession?

  /// Shared realtime hub (ADR-0028 §9) plus our subscription ids, so closing
  /// the messenger can drop ours without cutting the other product SDKs.
  private static var activeRealtime: RealtimeHub?
  private static var realtimeSubscriptions: [UUID] = []

  // MARK: - Lifecycle

  /// Prepares Support for this app, and says whether it may be used.
  ///
  /// Call it after `AppwinCore.configure(projectAppId:)` when you want to gate
  /// your own entry point (hide a help button, skip a tab). `presentMessenger()`
  /// also calls it on demand if you have not: a CTA can fire straight into the
  /// sheet without a prior `initialize()`.
  ///
  /// ```swift
  /// if await AppwinSupport.initialize().isReady {
  ///     showHelpButton = true
  /// }
  /// ```
  ///
  /// Idempotent, and cheap after the first call: the three products share one
  /// server round trip and its cached verdict.
  @discardableResult
  public static func initialize() async -> AppwinInitResult {
    AppwinCore.observeIdentity(.support) { change in handleIdentityChange(change) }
    let result = await AppwinCore.availability(of: .support)
    isReady = result.isReady
    if !result.isReady {
      AppwinCore.reportUnavailable(.support, result)
      SupportInAppWatcher.stop()
      AppwinPush.unregister(.support)
    } else {
      AppwinCore.reportMissingPushToken(for: .support)
      // From here on a reply announces itself wherever the customer is in the
      // app, not only inside the messenger. Lazy: the socket only opens when
      // this device has a conversation someone could actually reply to;
      // before that, the server notifies by push.
      SupportInAppWatcher.startIfNeeded()
      // Also replays the tap that cold-started the app, if one is waiting.
      AppwinPush.register(.support, handler: SupportPushHandler())
    }
    return result
  }

  /// Whether `initialize()` has returned `.ready`. Presentation is gated on it.
  public private(set) static var isReady = false

  // MARK: - Customer

  /// In-flight customer fetch, shared by concurrent callers.
  ///
  /// The messenger mounts several views that may all ask for the customer at
  /// once; without sharing, each would create its own server-side.
  private static var inFlightIdentify: Task<Customer, Error>?

  /// Bumped on every session change, so a fetch started for the previous
  /// customer does not overwrite the new one when it lands late.
  private static var identityGeneration = 0

  /// The customer the messenger displays, creating the lead on first use.
  ///
  /// Intercom model: opening the messenger creates a lead, so it works after
  /// `AppwinCore.configure` alone. Identity itself is Core's
  /// (`AppwinCore.identify` / `logout`); Support only reads the result.
  @discardableResult
  static func ensureCustomer() async throws -> Customer {
    if let customer { return customer }
    if let inFlight = inFlightIdentify { return try await inFlight.value }

    let task = Task { @MainActor in try await fetchCustomer() }
    inFlightIdentify = task
    defer { if inFlightIdentify == task { inFlightIdentify = nil } }
    return try await task.value
  }

  /// Re-fetches the customer, whose language inbound detection may have set.
  @discardableResult
  static func refreshCustomer() async throws -> Customer {
    try await fetchCustomer()
  }

  private static func handleIdentityChange(_ change: AppwinIdentityChange) {
    let wasLoaded = customer != nil || presentedSession != nil
    if change == .session {
      identityGeneration += 1
      customer = nil
      inFlightIdentify = nil
    }
    guard wasLoaded else { return }
    Task { @MainActor in _ = try? await refreshCustomer() }
  }

  /// `POST /support/v1/identify` with no attributes: resolves (or creates) the
  /// customer behind the current session. Attributes go through Core's
  /// `PATCH /sdk/v1/me`, never through here.
  private static func fetchCustomer() async throws -> Customer {
    guard let client = AppwinCore.client,
          let deviceId = AppwinCore.deviceId, !deviceId.isEmpty else {
      throw AppwinSupportError.notInitialized
    }
    // A launch that got `.ready` from the availability cache while
    // `/auth/init` failed has no bearer yet, and the guard would answer 401.
    if AuthSession.currentToken() == nil {
      _ = try await AppwinCore.bootstrapSession()
    }
    let generation = identityGeneration
    let customer: Customer = try await client.request(
      path: "/api/sdk/support/v1/identify",
      httpMethod: .post,
      body: DeviceAttributes(
        device: AppwinCore.deviceInfo?.model,
        os: AppwinCore.deviceInfo?.osVersion,
        appVersion: AppwinCore.deviceInfo?.appVersion
      )
    )
    if generation == identityGeneration {
      self.customer = customer
      presentedSession?.setCustomer(customer)
    }
    return customer
  }

  private struct DeviceAttributes: Encodable {
    let device: String?
    let os: String?
    let appVersion: String?
  }

  // MARK: - Presentation

  /// The conversation the messenger should open on, consumed by `HomeView`.
  ///
  /// A hand-off rather than a parameter: the router lives inside the view, and
  /// `presentMessenger` builds the tree before there is one to push onto.
  @MainActor
  static var pendingConversationId: String?

  /// Presents the messenger straight onto `id`.
  ///
  /// What the in-app banner and a push tap both need: landing on the home screen
  /// after being told "you have a reply" makes the reader hunt for it.
  @MainActor
  public static func presentConversation(id: String) {
    pendingConversationId = id
    presentMessenger()
  }

  /// Guards against double-taps while initialize / present is in flight.
  @MainActor
  private static var presentInFlight: Task<Void, Never>?

  /// Presents the messenger over the host app, as a sheet.
  ///
  /// Safe to call from a host button without gating on `initialize()` first:
  /// if Support is not ready yet, this runs initialization, opens the sheet
  /// when it can, and otherwise surfaces the reason on the shared in-app
  /// banner. A silent no-op is exactly the bug this path exists to avoid.
  @MainActor
  public static func presentMessenger() {
    if let presentInFlight {
      // Already opening: coalesce rather than stack sheets.
      _ = presentInFlight
      return
    }
    presentInFlight = Task { @MainActor in
      defer { presentInFlight = nil }
      await openMessenger()
    }
  }

  @MainActor
  private static func openMessenger() async {
    #if DEBUG
    print("[AppwinSupport] presentMessenger baseUrl=\(AppwinCore.baseUrl)")
    #endif
    let result = isReady ? AppwinInitResult.ready : await initialize()
    guard result.isReady else {
      #if DEBUG
      print("[AppwinSupport] presentMessenger not ready: \(result)")
      #endif
      AppwinCore.reportUnavailable(.support, result)
      presentFailure(userMessage(for: result))
      return
    }

    do {
      _ = try await ensureCustomer()
    } catch {
      #if DEBUG
      print(
        "[AppwinSupport] presentMessenger failed baseUrl=\(AppwinCore.baseUrl) "
          + "error=\(error)"
      )
      #endif
      presentFailure(String(format: SupportStrings.openFailedDetail, error.appwinUserMessage))
      return
    }

    guard let presenter = topViewController() else {
      presentFailure(SupportStrings.openFailed)
      return
    }

    // SwiftUI's `dismiss()` does not close a UIHostingController presented
    // from UIKit. Wire an explicit callback instead.
    var dismissPresented: (() -> Void)?
    guard let root = makeMessengerRoot(onClose: { dismissPresented?() }) else {
      presentFailure(SupportStrings.openFailed)
      return
    }

    let host = UIHostingController(rootView: root)
    host.modalPresentationStyle = .pageSheet
    if let sheet = host.sheetPresentationController {
      sheet.detents = [.large()]
      sheet.prefersGrabberVisible = false
      // Same radius the SwiftUI content clips itself to, or the two roundings
      // would not line up at the top of the panel.
      sheet.preferredCornerRadius = AppwinTheme.Radius().sheet
    }
    // Without this the UIKit chrome (nav bar, safe area, keyboard) follows the
    // host app's dark mode while the SwiftUI content stays light.
    host.overrideUserInterfaceStyle = .light
    presenter.present(host, animated: true)
    dismissPresented = { [weak host] in
      host?.dismiss(animated: true)
    }
  }

  /// Visible refusal: console alone is not enough when a host CTA fires this.
  @MainActor
  private static func presentFailure(_ body: String) {
    AppwinInAppBanner.present(
      AppwinBanner(
        id: "support:present-failed",
        title: SupportStrings.agentFallback,
        body: body
      )
    )
  }

  @MainActor
  private static func userMessage(for result: AppwinInitResult) -> String {
    switch result {
    case .ready:
      return ""
    case .notConfigured:
      return SupportStrings.notConfigured
    case .unknown:
      return SupportStrings.temporarilyUnavailable
    case .unavailable(.plan):
      return SupportStrings.planUnavailable
    case .unavailable(.disabled):
      return SupportStrings.disabledUnavailable
    }
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
    guard isReady else {
      AppwinCore.reportUnavailable(.support, .unavailable(.disabled))
      return AnyView(EmptyView())
    }
    return makeMessengerRoot() ?? AnyView(EmptyView())
  }

  /// Composition root, shared by both entry points, so the embedded and
  /// presented screens are literally the same. Two parallel constructions would
  /// diverge on the first change, and the bug would only show on one path.
  @MainActor
  private static func makeMessengerRoot(onClose: (() -> Void)? = nil) -> AnyView? {
    guard let client = AppwinCore.client else { return nil }

    // Shared stores are created here, once, and handed to the whole tree via
    // the Environment. Views pick them up with @EnvironmentObject; no store is
    // threaded through navigation as a parameter.
    // See docs/sdk-support-ios-state-management.md
    let session           = AppwinSession(customer: self.customer, client: client)
    presentedSession = session
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
      HomeView(onClose: onClose)
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
          if Self.presentedSession === session {
            Self.presentedSession = nil
          }
        }
    }
    return AnyView(root)
  }

  /// Topmost view controller, to present over.
  @MainActor
  private static func topViewController() -> UIViewController? {
    let scenes = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }
    let scene =
      scenes.first { $0.activationState == .foregroundActive }
      ?? scenes.first { $0.activationState == .foregroundInactive }
      ?? scenes.first
    let window =
      scene?.windows.first(where: \.isKeyWindow)
      ?? scene?.windows.first { !$0.isHidden && $0.alpha > 0 }
      ?? scene?.keyWindow
    guard var top = window?.rootViewController else { return nil }
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
