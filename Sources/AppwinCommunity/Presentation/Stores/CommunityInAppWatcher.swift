import Foundation
import AppwinCore

/// Turns an inbound community notification into an in-app banner.
///
/// The gap this closes: the server deliberately *skips* the push notification
/// when the customer has a live realtime connection - it assumes something
/// in-app will take over (`CommunityPushService`). Until now nothing did, so a
/// member sitting in the app on any screen other than that post was told
/// nothing at all.
///
/// Runs for the life of the process once Community is ready, not the life of
/// a screen.
///
/// Mirrors `SupportInAppWatcher` and Android's `CommunityInAppWatcher`.
@MainActor
enum CommunityInAppWatcher {

  private static var subscriptions: [UUID] = []
  private static var hub: RealtimeHub?

  /// Notifications older than this are not announced.
  ///
  /// Set when the watcher starts, so opening the app does not replay every
  /// notification received while it was closed - those already went out as push.
  private static var lastNotifiedAt = Date.distantPast

  static func start() {
    guard subscriptions.isEmpty, let realtime = AppwinCore.realtimeHub() else { return }
    hub = realtime
    lastNotifiedAt = Date()

    let check: @Sendable () -> Void = { Task { @MainActor in await self.check() } }
    subscriptions.append(realtime.on(event: "community.notification.created") { _ in check() })
    subscriptions.append(realtime.onConnected(check))
    realtime.start()
  }

  static func stop() {
    for id in subscriptions { hub?.off(id) }
    subscriptions = []
    hub = nil
  }

  private static func check() async {
    guard AppwinCore.client != nil else { return }
    let list = (try? await Factory.repository().notifications(limit: 20, offset: 0)) ?? []
    guard let newest = list.max(by: { $0.createdAt < $1.createdAt }) else { return }
    announceIfNew(newest)
  }

  private static func announceIfNew(_ notification: CommunityNotification) {
    let at = notification.createdAt
    guard at > lastNotifiedAt else { return }
    // Already reading that post: the detail is the notification.
    if let postId = notification.postId, postId == OpenPost.postId {
      lastNotifiedAt = at
      return
    }
    lastNotifiedAt = at

    let (title, body) = bannerCopy(notification)
    guard !body.isEmpty else { return }

    UnreadCountStore.refresh()
    let postId = notification.postId
    _ = AppwinInAppBanner.present(
      AppwinBanner(
        id: "community:\(notification.id)",
        title: title,
        body: body,
        onTap: {
          if let postId {
            AppwinCommunity.openPost(postId)
          } else {
            AppwinCommunity.presentCommunity()
          }
        }
      )
    )
  }

  /// Same shape as the server push copy (`CommunityPushService.copyFor`).
  static func bannerCopy(_ notification: CommunityNotification) -> (String, String) {
    let someone = CommunityStrings.notifSomeone
    let name = notification.actor?.nickname.trimmingCharacters(in: .whitespacesAndNewlines)
    let actor = (name?.isEmpty == false) ? name! : someone
    let excerpt = notification.excerpt?
      .trimmingCharacters(in: .whitespacesAndNewlines)
      .nilIfEmpty

    switch notification.type {
    case .postComment:
      let body = excerpt.map { String(format: CommunityStrings.notifBodyCommentedExcerpt, actor, $0) }
        ?? String(format: CommunityStrings.notifBodyCommented, actor)
      return (CommunityStrings.notifTitleComment, body)
    case .commentReply:
      let body = excerpt.map { String(format: CommunityStrings.notifBodyRepliedExcerpt, actor, $0) }
        ?? String(format: CommunityStrings.notifBodyReplied, actor)
      return (CommunityStrings.notifTitleReply, body)
    case .postReaction, .commentReaction:
      let body = excerpt.map { String(format: CommunityStrings.notifBodyLikedExcerpt, actor, $0) }
        ?? String(format: CommunityStrings.notifBodyLiked, actor)
      return (CommunityStrings.notifTitleReaction, body)
    case .pollVote:
      return (CommunityStrings.notifTitlePoll, String(format: CommunityStrings.notifBodyVoted, actor))
    case .adminPost:
      return (actor, excerpt ?? CommunityStrings.notifBodyAdminPost)
    case .contentRemoved:
      return (CommunityStrings.title, String(actor.prefix(80)))
    }
  }
}

private extension String {
  var nilIfEmpty: String? { isEmpty ? nil : self }
}
