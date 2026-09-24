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

/// Registered only while the feed is on screen: opening a post needs the
/// feed's navigation stack, so `AppwinPush` keeps a tap until the feed appears.
@MainActor
final class CommunityPushHandler: AppwinPushHandler {
  private let open: (CommunityPushTarget) -> Void

  init(open: @escaping (CommunityPushTarget) -> Void) {
    self.open = open
  }

  func onTap(_ payload: AppwinPushPayload) async {
    guard let target = CommunityPushTarget(payload) else { return }
    open(target)
  }
}
