import Foundation

/// Application sessions for analytics: UUIDv7 id, inactivity timeout, and the
/// reserved lifecycle events (`app_install`, `app_update`, `session_start`,
/// `session_end` with `duration_ms`).
///
/// State is persisted so a `session_end` can be emitted retroactively after a
/// process kill: on the next launch, a stale persisted session ends at its
/// last recorded activity, not at the relaunch instant. NOT thread-safe: the
/// EventPipeline actor is the only caller.
final class SessionManager {
  struct StandardEvent: Equatable {
    let name: String
    let sessionId: String
    let occurredAt: Date
    let durationMs: Int64?
  }

  private let prefs: AnalyticsPrefs
  private let keyPrefix: String
  private let appVersion: String?
  private let timeout: TimeInterval
  private let maxAge: TimeInterval
  private let now: () -> Date

  private(set) var sessionId: String?
  private var startedAt: Date?
  private var lastActiveAt: Date?
  private var lastPersistedActiveAt: Date?

  /// Re-persisting `lastActiveAt` on every event would hammer the disk;
  /// a 10 s granularity is invisible next to a 30 min timeout.
  private static let persistActiveInterval: TimeInterval = 10

  init(
    prefs: AnalyticsPrefs,
    keyPrefix: String,
    appVersion: String?,
    timeout: TimeInterval,
    maxAge: TimeInterval,
    now: @escaping () -> Date = Date.init
  ) {
    self.prefs = prefs
    self.keyPrefix = keyPrefix
    self.appVersion = appVersion
    self.timeout = timeout
    self.maxAge = maxAge
    self.now = now
    self.sessionId = prefs.string(forKey: keyPrefix + "session.id")
    self.startedAt = readDate("session.startedAt")
    self.lastActiveAt = readDate("session.lastActiveAt")
  }

  /// Called before any event is queued and on foreground. Returns the
  /// reserved events to queue first, and guarantees `sessionId` is set.
  func touch() -> [StandardEvent] {
    let at = now()
    var events: [StandardEvent] = []

    if let sessionId, let startedAt, let lastActiveAt {
      let expired = at.timeIntervalSince(lastActiveAt) > timeout
        || at.timeIntervalSince(startedAt) > maxAge
      if !expired {
        self.lastActiveAt = at
        persistActivityIfDue(at)
        return []
      }
      let duration = Int64((lastActiveAt.timeIntervalSince(startedAt) * 1000).rounded())
      events.append(StandardEvent(
        name: "session_end", sessionId: sessionId,
        occurredAt: lastActiveAt, durationMs: max(0, duration)))
    }

    var generator = SystemRandomNumberGenerator()
    let newId = Uuid7.generate(now: at, using: &generator)

    // Install and update lead the timeline of the session they open.
    if prefs.string(forKey: keyPrefix + "installTracked") == nil {
      prefs.set("1", forKey: keyPrefix + "installTracked")
      events.append(StandardEvent(name: "app_install", sessionId: newId, occurredAt: at, durationMs: nil))
    } else if let appVersion, let lastVersion = prefs.string(forKey: keyPrefix + "lastVersion"),
          lastVersion != appVersion {
      events.append(StandardEvent(name: "app_update", sessionId: newId, occurredAt: at, durationMs: nil))
    }
    prefs.set(appVersion, forKey: keyPrefix + "lastVersion")

    sessionId = newId
    startedAt = at
    lastActiveAt = at
    persistSession(at)
    events.append(StandardEvent(name: "session_start", sessionId: newId, occurredAt: at, durationMs: nil))
    return events
  }

  /// App left the foreground: record the activity boundary now, it is what
  /// a retroactive `session_end` will use after a kill.
  func onBackground() {
    let at = now()
    lastActiveAt = at
    persistSession(at)
  }

  /// Consent denied: forget the session, keep the install/version marks
  /// (a later re-consent must not re-emit `app_install`).
  func reset() {
    sessionId = nil
    startedAt = nil
    lastActiveAt = nil
    lastPersistedActiveAt = nil
    prefs.set(nil, forKey: keyPrefix + "session.id")
    prefs.set(nil, forKey: keyPrefix + "session.startedAt")
    prefs.set(nil, forKey: keyPrefix + "session.lastActiveAt")
  }

  // MARK: - Internals

  private func persistSession(_ at: Date) {
    prefs.set(sessionId, forKey: keyPrefix + "session.id")
    if let startedAt {
      prefs.set(String(Int64(startedAt.timeIntervalSince1970 * 1000)), forKey: keyPrefix + "session.startedAt")
    }
    prefs.set(String(Int64(at.timeIntervalSince1970 * 1000)), forKey: keyPrefix + "session.lastActiveAt")
    lastPersistedActiveAt = at
  }

  private func persistActivityIfDue(_ at: Date) {
    if let last = lastPersistedActiveAt, at.timeIntervalSince(last) < Self.persistActiveInterval { return }
    prefs.set(String(Int64(at.timeIntervalSince1970 * 1000)), forKey: keyPrefix + "session.lastActiveAt")
    lastPersistedActiveAt = at
  }

  private func readDate(_ suffix: String) -> Date? {
    guard let raw = prefs.string(forKey: keyPrefix + suffix), let ms = Int64(raw) else { return nil }
    return Date(timeIntervalSince1970: Double(ms) / 1000)
  }
}
