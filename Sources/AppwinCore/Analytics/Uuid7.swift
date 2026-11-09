import Foundation

/// UUIDv7 generator (RFC 9562): 48-bit Unix-ms timestamp, then random bits.
///
/// Analytics sessions use v7 so the id embeds its start time (the
/// raw_sessions_v3 pattern, cf. ADR-0041). No monotonic counter: the server
/// never orders events by session id, only groups by it.
enum Uuid7 {
  static func generate() -> String {
    var generator = SystemRandomNumberGenerator()
    return generate(now: Date(), using: &generator)
  }

  static func generate(now: Date, using generator: inout some RandomNumberGenerator) -> String {
    let timestampMs = UInt64(now.timeIntervalSince1970 * 1000)
    var bytes = [UInt8](repeating: 0, count: 16)
    for i in 0..<6 {
      bytes[i] = UInt8(truncatingIfNeeded: timestampMs >> (8 * (5 - i)))
    }
    for i in 6..<16 {
      bytes[i] = UInt8.random(in: .min ... .max, using: &generator)
    }
    bytes[6] = 0x70 | (bytes[6] & 0x0F)
    bytes[8] = 0x80 | (bytes[8] & 0x3F)

    let hex = bytes.map { String(format: "%02x", $0) }.joined()
    let start = hex.startIndex
    func slice(_ from: Int, _ to: Int) -> Substring {
      hex[hex.index(start, offsetBy: from)..<hex.index(start, offsetBy: to)]
    }
    return "\(slice(0, 8))-\(slice(8, 12))-\(slice(12, 16))-\(slice(16, 20))-\(slice(20, 32))"
  }

  /// Milliseconds embedded in the first 48 bits, for tests and file ordering.
  static func timestampMs(of uuid: String) -> UInt64? {
    let hex = uuid.replacingOccurrences(of: "-", with: "")
    guard hex.count == 32, let value = UInt64(hex.prefix(12), radix: 16) else { return nil }
    return value
  }
}
