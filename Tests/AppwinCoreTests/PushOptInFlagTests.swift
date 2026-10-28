import XCTest
@testable import AppwinCore

final class PushOptInFlagTests: XCTestCase {
  private let keyPrefix = "appwin.analytics.test."

  func testPushOptInIsClaimedOncePerInstall() {
    let prefs = InMemoryAnalyticsPrefs()
    XCTAssertTrue(PushOptInFlag.claim(
      prefs: prefs, keyPrefix: keyPrefix, freshInstall: true, grantedThisProcess: false))
    XCTAssertFalse(PushOptInFlag.claim(
      prefs: prefs, keyPrefix: keyPrefix, freshInstall: true, grantedThisProcess: true))
  }

  func testTheDecisionIsFreshInstallOrGrantSeenInProcessAndNeverTwice() {
    let cases: [(fresh: Bool, granted: Bool, claimed: Bool, emit: Bool)] = [
      (true, false, false, true),
      (false, true, false, true),
      (true, true, false, true),
      (false, false, false, false),
      (true, true, true, false),
    ]
    for c in cases {
      XCTAssertEqual(
        PushOptInFlag.shouldEmit(
          freshInstall: c.fresh, grantedThisProcess: c.granted, alreadyClaimed: c.claimed),
        c.emit, "\(c)")
    }
  }

  func testAnUpgradedAppEmitsNothingAndSetsTheFlagSilently() {
    let prefs = InMemoryAnalyticsPrefs()
    XCTAssertFalse(PushOptInFlag.claim(
      prefs: prefs, keyPrefix: keyPrefix, freshInstall: false, grantedThisProcess: false))
    XCTAssertEqual(prefs.string(forKey: keyPrefix + "pushOptIn.tracked"), "1")
  }

  func testAnInstallIsFreshOnlyWithoutAnyKnownDeviceOrFlag() {
    let prefs = InMemoryAnalyticsPrefs()
    XCTAssertTrue(SessionManager.isFreshInstall(
      prefs: prefs, keyPrefix: keyPrefix, deviceKnownBeforeConfigure: false))
    XCTAssertFalse(SessionManager.isFreshInstall(
      prefs: prefs, keyPrefix: keyPrefix, deviceKnownBeforeConfigure: true))
    prefs.set("1", forKey: keyPrefix + "cv.registered")
    XCTAssertFalse(SessionManager.isFreshInstall(
      prefs: prefs, keyPrefix: keyPrefix, deviceKnownBeforeConfigure: false))
    let tracked = InMemoryAnalyticsPrefs()
    tracked.set("1", forKey: keyPrefix + "installTracked")
    XCTAssertFalse(SessionManager.isFreshInstall(
      prefs: tracked, keyPrefix: keyPrefix, deviceKnownBeforeConfigure: false))
  }
}
