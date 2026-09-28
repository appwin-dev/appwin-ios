import Foundation
import AppwinCore

/// Community push target: a post, optionally the replies thread under one comment.
struct CommunityPushTarget: Equatable, Sendable {
  let postId: String
  /// Root comment id: opens the dedicated replies screen.
  let threadCommentId: String?

  init(postId: String, threadCommentId: String? = nil) {
    self.postId = postId
    self.threadCommentId = threadCommentId
  }

  /// `appwin://community/post/{id}[/thread/{rootCommentId}]` (see `appwinPushRoutes` in the contract).
  init?(_ payload: AppwinPushPayload) {
    guard let deeplink = payload.deeplink,
          let url = URL(string: deeplink),
          let route = AppwinPushPayload.route(of: url),
          route.product == AppwinProduct.community.rawValue,
          route.path.count >= 2, route.path[0] == "post", !route.path[1].isEmpty
    else { return nil }
    let thread = route.path.count >= 4 && route.path[2] == "thread" && !route.path[3].isEmpty
      ? route.path[3] : nil
    self.init(postId: route.path[1], threadCommentId: thread)
  }
}

/// Community's single handler in `AppwinPush`, registered by `initialize()` as
/// soon as the verdict is ready and never unregistered.
///
/// It used to live and die with the feed's `onAppear`, which lost every tap
/// arriving while Community sat in a tab the member was not looking at.
@MainActor
final class CommunityPushRouter: AppwinPushHandler {
  static let shared = CommunityPushRouter()

  private var registered = false

  func registerIfNeeded() {
    guard !registered else { return }
    registered = true
    AppwinPush.register(.community, handler: self)
  }

  func onTap(_ payload: AppwinPushPayload) async {
    UnreadCountStore.refresh()
    guard let target = CommunityPushTarget(payload) else { return }
    AppwinCommunity.routeNotificationTap(target)
  }

  func onForeground(_ payload: AppwinPushPayload) -> Bool {
    UnreadCountStore.refresh()
    return false
  }

  func onMessage(_ payload: AppwinPushPayload) async -> Bool {
    UnreadCountStore.refresh()
    return false
  }
}
