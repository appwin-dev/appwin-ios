import Foundation

/// `REPLAY_LIMITS` of `@app-win/contracts`, shared by every SDK.
enum ReplayLimits {
  static let segmentFrames = 10
  static let frameInterval: TimeInterval = 1
  static let captureScale: CGFloat = 2
  static let videoBitrate = 400_000
  static let keyFrameInterval = 10
  static let maxSessionSeconds = 3600
  static let segmentMaxBytes = 2 * 1024 * 1024
  static let queueMaxBytes = 20 * 1024 * 1024
  static let maxTouches = 1000
  static let maxScreens = 100
  static let maxOffsetMs = 600_000
}

enum ReplaySampling {
  /// Decided from the session id alone, so a relaunch inside the same session
  /// keeps the verdict without storing it. The LAST 8 hex digits: a UUIDv7
  /// starts with its timestamp, which would put every session of the same
  /// minute on the same side of the rate.
  static func isSampled(sessionId: String, rate: Double) -> Bool {
    let hex = sessionId.replacingOccurrences(of: "-", with: "")
    guard hex.count >= 8, let value = UInt32(hex.suffix(8), radix: 16) else { return false }
    return Double(value) / 4_294_967_296 < rate
  }
}

/// The `meta` field of `POST /api/sdk/v1/replays/segments`
/// (`ReplaySegmentMetaSchema`). Frozen once shipped (ADR-0052).
struct ReplaySegmentMeta: Codable, Equatable, Sendable {
  struct Touch: Codable, Equatable, Sendable {
    let t: Int
    let x: Double
    let y: Double
  }

  struct Screen: Codable, Equatable, Sendable {
    let t: Int
    let name: String
  }

  var sessionId: String
  var seq: Int
  var kind = "video"
  var runtime: String
  var startedAt: String
  var endedAt: String
  var sentAt: String
  var width: Int
  var height: Int
  var screens: [Screen]
  var touches: [Touch]

  static let iso8601 = Date.ISO8601FormatStyle(includingFractionalSeconds: true)

  static func timestamp(_ date: Date) -> String { date.formatted(iso8601) }

  /// The bytes sent: `sentAt` is stamped at send time, like the events do, so
  /// the server can correct a skewed device clock.
  func encoded(sentAt: Date) throws -> Data {
    var copy = self
    copy.sentAt = Self.timestamp(sentAt)
    return try JSONEncoder().encode(copy)
  }
}

/// Where a recording stands in its session, persisted so a relaunch inside
/// the same session continues the numbering: `(sessionId, seq)` is the
/// server's dedup key, and restarting at 0 would overwrite earlier segments.
struct ReplaySessionState: Codable, Equatable {
  var sessionId: String
  var nextSeq = 0
  var recordedSeconds = 0

  var budgetExhausted: Bool { recordedSeconds >= ReplayLimits.maxSessionSeconds }

  static func load(key: String, defaults: UserDefaults = .standard) -> ReplaySessionState? {
    defaults.data(forKey: key).flatMap { try? JSONDecoder().decode(Self.self, from: $0) }
  }

  func save(key: String, defaults: UserDefaults = .standard) {
    if let data = try? JSONEncoder().encode(self) { defaults.set(data, forKey: key) }
  }
}
