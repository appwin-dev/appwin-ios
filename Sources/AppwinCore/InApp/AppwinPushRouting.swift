import Foundation

/// Host / product routing for Appwin push deeplinks.
///
/// Notifications must not import Support (sibling targets). Support registers a
/// handler at `initialize()` so a Support push tap can open the messenger.
public enum AppwinPushRouting {
  /// Return `true` when the deeplink was consumed (do not also open the URL).
  @MainActor
  public static var handleDeeplink: ((URL) -> Bool)?

  /// `appwin://support/conversation/{id}` → conversation id.
  public static func supportConversationId(from url: URL) -> String? {
    guard url.scheme == "appwin" else { return nil }
    let host = (url.host ?? "").lowercased()
    let parts = url.pathComponents.filter { $0 != "/" }
    // appwin://support/conversation/{id}
    if host == "support", parts.count >= 2, parts[0] == "conversation" {
      let id = parts[1]
      return id.isEmpty ? nil : id
    }
    // appwin:///support/conversation/{id}
    if parts.count >= 3, parts[0] == "support", parts[1] == "conversation" {
      let id = parts[2]
      return id.isEmpty ? nil : id
    }
    return nil
  }

  public static func isSupportConversationDeeplink(_ url: URL) -> Bool {
    supportConversationId(from: url) != nil
  }
}
