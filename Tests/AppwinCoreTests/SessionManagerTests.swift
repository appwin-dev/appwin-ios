import XCTest
@testable import AppwinCore

final class SessionManagerTests: XCTestCase {
  private var prefs: InMemoryAnalyticsPrefs!
  private var nowMs: Int64 = 1_788_500_000_000

  override func setUp() {
    super.setUp()
    prefs = InMemoryAnalyticsPrefs()
    nowMs = 1_788_500_000_000
  }

  private func makeManager(appVersion: String? = "1.0.0") -> SessionManager {
    SessionManager(
      prefs: prefs, keyPrefix: "appwin.analytics.test.", appVersion: appVersion,
      timeout: 30 * 60, maxAge: 24 * 3600,
      now: { Date(timeIntervalSince1970: Double(self.nowMs) / 1000) })
  }

  private func advance(seconds: Int64) { nowMs += seconds * 1000 }

  func testFirstTouchEmitsInstallThenSessionStart() {
    let manager = makeManager()
    let events = manager.touch()
    XCTAssertEqual(events.map(\.name), ["app_install", "session_start"])
    XCTAssertEqual(events[0].sessionId, events[1].sessionId)
    XCTAssertEqual(manager.sessionId, events[1].sessionId)
    XCTAssertNotNil(prefs.string(forKey: "appwin.analytics.test.session.id"))
  }

  func testTouchWithinTimeoutKeepsTheSession() {
    let manager = makeManager()
    let started = manager.touch()
    advance(seconds: 60)
    XCTAssertEqual(manager.touch(), [])
    XCTAssertEqual(manager.sessionId, started.last?.sessionId)
  }

  func testTouchAfterTimeoutEndsRetroactivelyAndStartsANewSession() {
    let manager = makeManager()
    let first = manager.touch()
    advance(seconds: 5)
    _ = manager.touch()
    let lastActive = nowMs
    advance(seconds: 31 * 60)
    let events = manager.touch()
    XCTAssertEqual(events.map(\.name), ["session_end", "session_start"])
    XCTAssertEqual(events[0].sessionId, first.last?.sessionId)
    XCTAssertEqual(events[0].occurredAt, Date(timeIntervalSince1970: Double(lastActive) / 1000))
    XCTAssertEqual(events[0].durationMs, 5_000)
    XCTAssertNotEqual(events[1].sessionId, first.last?.sessionId)
  }

  func testRelaunchWithinTimeoutResumesTheSession() {
    let manager = makeManager()
    let started = manager.touch()
    advance(seconds: 60)
    let relaunched = makeManager()
    XCTAssertEqual(relaunched.touch(), [])
    XCTAssertEqual(relaunched.sessionId, started.last?.sessionId)
  }

  func testRelaunchAfterTimeoutEndsFromPersistedStateWithoutReinstall() {
    let manager = makeManager()
    let first = manager.touch()
    let startMs = nowMs
    advance(seconds: 45 * 60)
    let relaunched = makeManager()
    let events = relaunched.touch()
    XCTAssertEqual(events.map(\.name), ["session_end", "session_start"])
    XCTAssertEqual(events[0].sessionId, first.last?.sessionId)
    XCTAssertEqual(events[0].occurredAt, Date(timeIntervalSince1970: Double(startMs) / 1000))
    XCTAssertEqual(events[0].durationMs, 0)
  }

  func testMaxAgeRecyclesAnActiveSession() {
    let manager = makeManager()
    let first = manager.touch()
    for _ in 0..<146 {
      advance(seconds: 10 * 60)
      _ = manager.touch()
    }
    let names = Set([first.last?.sessionId, manager.sessionId])
    XCTAssertEqual(names.count, 2, "a session older than maxAge must have been recycled")
  }

  func testAppUpdateIsEmittedOnceOnVersionChange() {
    _ = makeManager().touch()
    advance(seconds: 45 * 60)
    let updated = makeManager(appVersion: "2.0.0")
    let events = updated.touch()
    XCTAssertEqual(events.map(\.name), ["session_end", "app_update", "session_start"])
    advance(seconds: 45 * 60)
    let again = makeManager(appVersion: "2.0.0")
    XCTAssertEqual(again.touch().map(\.name), ["session_end", "session_start"])
  }

  func testResetForgetsSessionButNotInstall() {
    let manager = makeManager()
    _ = manager.touch()
    manager.reset()
    XCTAssertNil(manager.sessionId)
    let events = manager.touch()
    XCTAssertEqual(events.map(\.name), ["session_start"])
  }

  func testConsentDefaultsToGrantedAndPersists() {
    let store = ConsentStore(prefs: prefs, keyPrefix: "appwin.analytics.test.")
    XCTAssertEqual(store.consent, .granted)
    store.set(.denied)
    let reloaded = ConsentStore(prefs: prefs, keyPrefix: "appwin.analytics.test.")
    XCTAssertEqual(reloaded.consent, .denied)
  }

  func testInitialConsentOverridesTheDefaultSynchronously() {
    let store = ConsentStore(prefs: prefs, keyPrefix: "appwin.analytics.test.", initial: .unknown)
    XCTAssertEqual(store.consent, .unknown)
    let reloaded = ConsentStore(prefs: prefs, keyPrefix: "appwin.analytics.test.")
    XCTAssertEqual(reloaded.consent, .unknown)
  }
}
