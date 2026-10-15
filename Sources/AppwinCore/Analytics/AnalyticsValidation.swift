import Foundation

/// Client-side validation of event names and props, mirroring the server
/// contract. Failing early matters: the server counts an invalid event in
/// `rejected` and moves on, which an integrator would never see.
enum AnalyticsValidation {
  /// Emitted by the SDK itself; a custom event must not shadow them.
  static let reservedNames: Set<String> = [
    "session_start", "session_end", "screen_view", "app_install", "app_update",
    "install_referrer",
  ]

  static let maxPropsCount = 20
  static let maxPropKeyLength = 64
  static let maxPropStringLength = 256
  static let maxScreenLength = 128

  /// Server rule: `^[a-z][a-z0-9_]{0,63}$`, spelled out to stay allocation-free.
  static func isValidEventName(_ name: String) -> Bool {
    guard (1...64).contains(name.count), let first = name.unicodeScalars.first else { return false }
    guard ("a"..."z").contains(Character(first)) else { return false }
    return name.unicodeScalars.allSatisfy { scalar in
      let c = Character(scalar)
      return ("a"..."z").contains(c) || ("0"..."9").contains(c) || c == "_"
    }
  }

  /// Drops oversized keys, truncates long strings, caps the count at 20
  /// (alphabetical order, so which keys survive is deterministic).
  static func sanitizeProps(_ props: [String: AnalyticsValue]?) -> [String: AnalyticsValue]? {
    guard let props, !props.isEmpty else { return nil }
    var out: [String: AnalyticsValue] = [:]
    for key in props.keys.sorted() {
      if out.count >= maxPropsCount { break }
      guard !key.isEmpty, key.count <= maxPropKeyLength else { continue }
      switch props[key]! {
      case .string(let value):
        out[key] = .string(String(value.prefix(maxPropStringLength)))
      case let value:
        out[key] = value
      }
    }
    return out.isEmpty ? nil : out
  }
}
