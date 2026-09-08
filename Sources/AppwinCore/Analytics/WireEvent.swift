import Foundation

/// Serializes one event to its wire form (the exact JSON object the server
/// ingests) at `track` time. The disk queue stores wire lines, so what is
/// stored IS what is sent: no re-mapping at flush time, no schema drift
/// between the two.
enum WireEvent {
  private static let iso8601 = Date.ISO8601FormatStyle(includingFractionalSeconds: true)

  static func line(
    name: String,
    occurredAt: Date,
    sessionId: String?,
    screen: String?,
    props: [String: AnalyticsValue]?
  ) -> String? {
    var object: [String: Any] = [
      "eventId": UUID().uuidString.lowercased(),
      "name": name,
      "occurredAt": occurredAt.formatted(iso8601),
    ]
    if let sessionId { object["sessionId"] = sessionId }
    if let screen { object["screen"] = screen }
    if let props, !props.isEmpty {
      object["props"] = props.mapValues(\.jsonValue)
    }
    guard let data = try? JSONSerialization.data(withJSONObject: object) else { return nil }
    return String(decoding: data, as: UTF8.self)
  }
}
