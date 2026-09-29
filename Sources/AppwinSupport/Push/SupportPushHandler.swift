import Foundation
import AppwinCore

/// Support's side of `AppwinPush`: a reply push opens its conversation, and
/// in the foreground becomes the in-app banner instead of a system one.
@MainActor
final class SupportPushHandler: AppwinPushHandler {

  func onTap(_ payload: AppwinPushPayload) async {
    guard let conversationId = Self.conversationId(of: payload) else {
      AppwinSupport.presentMessenger()
      return
    }
    // Waits for initialize and the customer session itself: this may run
    // right after a cold start.
    AppwinSupport.presentConversation(id: conversationId)
  }

  func onForeground(_ payload: AppwinPushPayload) -> Bool {
    guard let conversationId = Self.conversationId(of: payload) else { return false }
    // Already reading that thread: the bubble is the notification.
    if conversationId == OpenThread.conversationId { return true }
    let title = payload.title?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
    let body = payload.body?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
    guard !body.isEmpty else { return false }
    // `false` when the host has no attachable window (classic RN UIWindow): the
    // system banner then stays, rather than the reply going unannounced.
    return AppwinInAppBanner.present(
      AppwinBanner(
        id: "support-push:\(conversationId)",
        title: title.isEmpty ? SupportStrings.agentFallback : title,
        body: body,
        onTap: { AppwinSupport.presentConversation(id: conversationId) }
      )
    )
  }

  /// `appwin://support/conversation/{id}` to `{id}`.
  nonisolated static func conversationId(of payload: AppwinPushPayload) -> String? {
    guard let deeplink = payload.deeplink,
          let url = URL(string: deeplink),
          let route = AppwinPushPayload.route(of: url),
          route.product == AppwinProduct.support.rawValue,
          route.path.count >= 2, route.path[0] == "conversation",
          !route.path[1].isEmpty
    else { return nil }
    return route.path[1]
  }
}
