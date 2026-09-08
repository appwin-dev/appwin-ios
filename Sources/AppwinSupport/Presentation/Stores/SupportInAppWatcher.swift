import Foundation
import AppwinCore

/// Turns an inbound support reply into an in-app banner.
///
/// The gap this closes: the server deliberately *skips* the push notification
/// when the customer has a live realtime connection - it assumes something
/// in-app will take over (`SupportCustomerPushService.notifyAgentReply`). Until
/// now nothing did, so a customer sitting in the app on any screen other than
/// the messenger was told nothing at all.
///
/// Runs for the life of the process, not the life of a screen. `makeMessengerRoot`
/// also subscribes to these events, but only while the messenger is mounted,
/// which is precisely the case where a banner is *not* wanted.
///
/// Mirrors `SupportInAppWatcher` on Android.
@MainActor
enum SupportInAppWatcher {

  private static var subscriptions: [UUID] = []
  private static var hub: RealtimeHub?
  private static var configStore: ConfigStore?

  /// Messages older than this are not announced.
  ///
  /// Set when the watcher starts, so opening the app does not replay every reply
  /// received while it was closed - those already went out as push.
  private static var lastNotifiedAt = Date.distantPast

  private static var hasConversationsKey: String {
    "appwin.support.hasConversations.\(AppwinCore.projectAppId ?? "")"
  }

  /// Whether this device is known to have at least one support conversation.
  /// Persisted: on the next launch `initialize()` reads it to decide whether
  /// the socket is worth opening at all.
  private static var hasConversations: Bool {
    UserDefaults.standard.bool(forKey: hasConversationsKey)
  }

  /// Called by `initialize()`: no conversation means nobody can reply, so
  /// there is nothing to listen for - the socket would be a per-user cost
  /// with no upside. Until it opens, the server falls back to push.
  static func startIfNeeded() {
    guard hasConversations else { return }
    start()
  }

  /// A conversation was seen (non-empty list) or just created: from now on a
  /// reply can arrive, so the watcher must be listening - this launch and
  /// the next ones.
  static func noteConversationsExist() {
    if !hasConversations {
      UserDefaults.standard.set(true, forKey: hasConversationsKey)
    }
    start()
  }

  static func start() {
    guard subscriptions.isEmpty, let realtime = AppwinCore.realtimeHub() else { return }
    hub = realtime
    lastNotifiedAt = Date()

    // The studio's palette and agent name, read from the on-disk cache so the
    // first banner is already branded rather than generic.
    let store = Factory.makeConfigStore(appId: AppwinCore.projectAppId ?? "")
    store.loadCache()
    configStore = store

    let check: @Sendable () -> Void = { Task { @MainActor in await self.check() } }
    // The same refetch on both: the events carry a minimal payload (a message id
    // and the customer), so the conversation list is what says who wrote and what
    // the preview is. `onConnected` covers a reply that landed while the socket
    // was down.
    subscriptions.append(realtime.on(event: "support.message.created") { _ in check() })
    subscriptions.append(realtime.onConnected(check))
    realtime.start()
  }

  static func stop() {
    for id in subscriptions { hub?.off(id) }
    subscriptions = []
    hub = nil
    configStore = nil
  }

  private static func check() async {
    guard AppwinCore.client != nil else { return }
    let repo = ApiConversationRepository(clientApi: AppwinCore.client!)
    let page = try? await GetAllConversationsUseCase(repo: repo).execute(limit: 20)
    guard let newest = page?.items.max(by: { lhs, rhs in
      (lhs.lastMessageAt ?? lhs.createdAt) < (rhs.lastMessageAt ?? rhs.createdAt)
    }) else { return }

    announceIfInbound(newest)
  }

  private static func announceIfInbound(_ conversation: Conversation) {
    guard let at = conversation.lastMessageAt else { return }
    // The customer's own message raises the same event; only the studio's is
    // news to them.
    guard conversation.lastMessageAuthorType?.isStudio == true else { return }
    // Already reading that thread: the bubble is the notification.
    guard conversation.id != OpenThread.conversationId else { return }
    guard at > lastNotifiedAt else { return }
    lastNotifiedAt = at

    let preview = conversation.preview?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
    guard !preview.isEmpty else { return }

    let config = configStore?.config
    let conversationId = conversation.id

    AppwinInAppBanner.present(
      AppwinBanner(
        // Keyed by the message date, so a reconnect that replays the same
        // conversation does not stack a second banner.
        id: "support:\(conversationId):\(at.timeIntervalSince1970)",
        title: agentName(from: config),
        body: preview,
        accentHex: config?.branding.accentHex,
        onTap: { AppwinSupport.presentConversation(id: conversationId) }
      )
    )
  }

  /// Same fallback chain the thread header uses: the studio's agent name, then
  /// the project's, then the generic label.
  private static func agentName(from config: MessengerConfig?) -> String {
    guard let config else { return "Support" }
    if let name = config.messaging.agentName, !name.isEmpty { return name }
    if !config.context.agentName.isEmpty { return config.context.agentName }
    if !config.context.projectName.isEmpty { return config.context.projectName }
    return "Support"
  }
}
