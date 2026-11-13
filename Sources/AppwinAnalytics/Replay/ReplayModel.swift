import Foundation
import QuartzCore

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

/// When the next frame is taken. A native capture holds the main thread for
/// about 40 ms (iPhone 15), which shows as a stutter on anything moving and
/// as nothing on a still screen. So a due frame waits while a finger is on
/// the screen, a scroll view is tracking or the main thread animates, and for
/// `settle` after the last touch, while a fling or a transition plays out.
/// Past `maxGap` since the previous frame it is taken anyway: a screen that
/// never stops moving would otherwise never be recorded.
struct ReplayPacer {
  static let poll: TimeInterval = 0.25
  static let settle: TimeInterval = 1
  static let maxGap: TimeInterval = 10

  static func isDue(
    now: Date, lastFrameAt: Date?, touching: Bool, lastTouchAt: Date?, scrolling: Bool,
    animating: Bool = false
  ) -> Bool {
    guard let lastFrameAt else { return true }
    let elapsed = now.timeIntervalSince(lastFrameAt)
    // Half a poll of slack: the timer fires on a 0.25 s grid, a strict
    // comparison would push every frame one poll late.
    guard elapsed >= ReplayLimits.frameInterval - poll / 2 else { return false }
    if elapsed >= maxGap { return true }
    if touching || scrolling || animating { return false }
    if let lastTouchAt, now.timeIntervalSince(lastTouchAt) < settle { return false }
    return true
  }
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

/// Whether the main thread is animating, read from its run loop: an animation
/// driven from it (Lottie, SwiftUI, a display link, Flutter's frames on the
/// platform thread) wakes it once per frame, a still app a few times a
/// second. Core Animation animations run in the render server and wake
/// nothing: a capture does not stutter them.
@MainActor
final class ReplayMainThreadActivity {
  nonisolated static let window: CFTimeInterval = 0.25
  /// A quarter second is 15 frames at 60 Hz; at rest, the recorder's own
  /// poll accounts for one wake-up.
  nonisolated static let animatingWakeups = 6

  private var wakeups: [CFTimeInterval] = []
  private var observer: CFRunLoopObserver?

  func start() {
    guard observer == nil else { return }
    let observer = CFRunLoopObserverCreateWithHandler(
      nil, CFRunLoopActivity.afterWaiting.rawValue, true, 0
    ) { [weak self] _, _ in
      MainActor.assumeIsolated { self?.record(CACurrentMediaTime()) }
    }
    CFRunLoopAddObserver(CFRunLoopGetMain(), observer, .commonModes)
    self.observer = observer
  }

  func stop() {
    if let observer { CFRunLoopObserverInvalidate(observer) }
    observer = nil
    wakeups.removeAll()
  }

  var isAnimating: Bool { Self.isAnimating(wakeups, now: CACurrentMediaTime()) }

  nonisolated static func isAnimating(_ wakeups: [CFTimeInterval], now: CFTimeInterval) -> Bool {
    wakeups.reduce(0) { $0 + (now - $1 <= window ? 1 : 0) } >= animatingWakeups
  }

  private func record(_ time: CFTimeInterval) {
    wakeups.append(time)
    if wakeups.count > 64 { wakeups.removeFirst(wakeups.count - 32) }
  }
}
