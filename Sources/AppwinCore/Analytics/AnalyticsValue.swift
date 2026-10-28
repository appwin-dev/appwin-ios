import Foundation

/// A property value on an analytics event: string, number or boolean,
/// mirroring the server contract (no nested objects, no arrays).
///
/// Literal-expressible so call sites read naturally:
/// `AppwinAnalytics.track("purchase", props: ["plan": "pro", "seats": 3, "trial": false])`
public enum AnalyticsValue: Sendable, Equatable {
  case string(String)
  case int(Int)
  case double(Double)
  case bool(Bool)

  /// Public: adapter modules (AppwinTikTokEvents) unwrap props for their SDK.
  public var jsonValue: Any {
    switch self {
    case .string(let value): return value
    case .int(let value): return value
    case .double(let value): return value
    case .bool(let value): return value
    }
  }
}

extension AnalyticsValue: ExpressibleByStringLiteral {
  public init(stringLiteral value: String) { self = .string(value) }
}

extension AnalyticsValue: ExpressibleByIntegerLiteral {
  public init(integerLiteral value: Int) { self = .int(value) }
}

extension AnalyticsValue: ExpressibleByFloatLiteral {
  public init(floatLiteral value: Double) { self = .double(value) }
}

extension AnalyticsValue: ExpressibleByBooleanLiteral {
  public init(booleanLiteral value: Bool) { self = .bool(value) }
}
