import Foundation

/// Superseded by `AppwinPush`, which every product now registers with.
public enum AppwinPushRouting {
  /// No longer consulted: Support registers with `AppwinPush` itself, and a hook
  /// set here before that happened is exactly what lost cold-start taps.
  @available(*, deprecated, message: "Ignored. Forward pushes with AppwinPush.handleTap(_:).")
  @MainActor
  public static var handleDeeplink: ((URL) -> Bool)?

  /// `appwin://support/conversation/{id}` to `{id}`.
  @available(*, deprecated, message: "Internal to AppwinSupport from now on.")
  public static func supportConversationId(from url: URL) -> String? {
    guard let route = AppwinPushPayload.route(of: url),
          route.product == AppwinProduct.support.rawValue,
          route.path.count >= 2, route.path[0] == "conversation",
          !route.path[1].isEmpty
    else { return nil }
    return route.path[1]
  }

  @available(*, deprecated, message: "Use AppwinPush.isAppwinPush(_:).")
  public static func isSupportConversationDeeplink(_ url: URL) -> Bool {
    supportConversationId(from: url) != nil
  }
}
