import Foundation

/// An Appwin push, parsed once from whatever the transport delivered.
///
/// Wire contract: `packages/contracts/src/sdk-identity/sdk-push.ts`. Flat string
/// keys at the APNs root (beside `aps`) or in FCM `data`; some legacy payloads
/// nest them under `data`, which is read too.
///
/// Sendable on purpose: the raw `userInfo` is not, and a tap has to cross from
/// the notification delegate to the main actor, and sometimes wait in a queue.
package struct AppwinPushPayload: Sendable, Equatable {
  /// `appwinType`, e.g. `support.message`. `nil` on legacy pushes.
  package let type: String?
  /// The product that handles this push: `support`, `notifications`, ...
  package let product: String
  package let deeplink: String?
  package let deliveryId: String?
  package let imageUrl: String?
  package let title: String?
  package let body: String?
  /// Every string value of the payload, nested `data` keys included.
  package let raw: [String: String]

  package init(
    type: String?,
    product: String,
    deeplink: String? = nil,
    deliveryId: String? = nil,
    imageUrl: String? = nil,
    title: String? = nil,
    body: String? = nil,
    raw: [String: String] = [:]
  ) {
    self.type = type
    self.product = product
    self.deeplink = deeplink
    self.deliveryId = deliveryId
    self.imageUrl = imageUrl
    self.title = title
    self.body = body
    self.raw = raw
  }

  /// `nil` when `data` is not an Appwin push.
  ///
  /// `title` / `body` override the ones read from `aps.alert`: the notification
  /// delegate has the rendered content, localized keys resolved.
  package init?(_ data: [AnyHashable: Any], title: String? = nil, body: String? = nil) {
    let raw = Self.flatten(data)
    let type = raw[Keys.type]
    let deeplink = raw[Keys.deeplink]
    let deliveryId = raw[Keys.deliveryId]
    guard let product = Self.product(type: type, deeplink: deeplink, deliveryId: deliveryId) else {
      return nil
    }
    let alert = Self.alert(in: data)
    self.init(
      type: type,
      product: product,
      deeplink: deeplink,
      deliveryId: deliveryId,
      imageUrl: raw[Keys.imageUrl],
      title: Self.nonEmpty(title) ?? alert.title,
      body: Self.nonEmpty(body) ?? alert.body,
      raw: raw
    )
  }

  /// A tap on an internal route that did not come from a push (an in-app
  /// message button, a campaign deeplink pointing at another product).
  package init?(deeplink url: URL) {
    guard let route = AppwinPushPayload.route(of: url) else { return nil }
    self.init(type: nil, product: route.product, deeplink: url.absoluteString)
  }

  /// `appwin://<product>/<path...>` split into its parts, `nil` for any other URL.
  ///
  /// Also accepts `appwin:///<product>/...`, which older servers emitted.
  package static func route(of url: URL) -> (product: String, path: [String])? {
    guard url.scheme?.lowercased() == scheme else { return nil }
    var parts = url.pathComponents.filter { $0 != "/" }
    var product = (url.host ?? "").lowercased()
    if product.isEmpty {
      guard !parts.isEmpty else { return nil }
      product = parts.removeFirst().lowercased()
    }
    return (product, parts)
  }

  package static let scheme = "appwin"

  enum Keys {
    static let type = "appwinType"
    static let deeplink = "deeplink"
    static let deliveryId = "deliveryId"
    static let imageUrl = "imageUrl"
  }

  /// `inapp.pending` predates the `<product>.<event>` naming (SDKs up to 0.7
  /// match it verbatim), so it is mapped by hand.
  static func product(type: String?, deeplink: String?, deliveryId: String?) -> String? {
    if let type {
      if type == "inapp.pending" { return AppwinProduct.notifications.rawValue }
      let prefix = type.split(separator: ".", maxSplits: 1).first.map(String.init) ?? type
      return prefix.isEmpty ? nil : prefix
    }
    // Legacy pushes, sent before `appwinType` existed.
    if let deeplink, let url = URL(string: deeplink), let route = route(of: url) {
      return route.product
    }
    if deliveryId != nil { return AppwinProduct.notifications.rawValue }
    return nil
  }

  private static func flatten(_ data: [AnyHashable: Any]) -> [String: String] {
    var raw: [String: String] = [:]
    if let nested = data["data"] as? [AnyHashable: Any] {
      for case let (key as String, value as String) in nested where !value.isEmpty {
        raw[key] = value
      }
    }
    // Root keys win over nested ones: the root is the current contract.
    for case let (key as String, value as String) in data where !value.isEmpty {
      raw[key] = value
    }
    return raw
  }

  private static func alert(in data: [AnyHashable: Any]) -> (title: String?, body: String?) {
    guard let aps = data["aps"] as? [AnyHashable: Any] else { return (nil, nil) }
    if let alert = aps["alert"] as? [AnyHashable: Any] {
      return (nonEmpty(alert["title"] as? String), nonEmpty(alert["body"] as? String))
    }
    return (nil, nonEmpty(aps["alert"] as? String))
  }

  private static func nonEmpty(_ value: String?) -> String? {
    guard let value, !value.isEmpty else { return nil }
    return value
  }
}
