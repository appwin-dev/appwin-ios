import XCTest
@_spi(Appwin) @testable import AppwinCore

final class ConsentStoreTests: XCTestCase {
  func testLegacySingleKeyIsSpreadOverTheThreePurposesThenDropped() {
    let prefs = InMemoryAnalyticsPrefs()
    prefs.set("denied", forKey: "appwin.analytics.test.consent")
    let store = ConsentStore(prefs: prefs, keyPrefix: "appwin.analytics.test.")
    XCTAssertEqual(store.state(for: .analytics), .denied)
    XCTAssertEqual(store.state(for: .marketing), .denied)
    XCTAssertEqual(store.state(for: .advertising), .denied)
    XCTAssertEqual(prefs.string(forKey: "appwin.analytics.test.consent.marketing"), "denied")
    XCTAssertNil(prefs.string(forKey: "appwin.analytics.test.consent"))
  }

  func testLegacyKeyIsAlsoReadWithoutAStore() {
    let prefs = InMemoryAnalyticsPrefs()
    prefs.set("denied", forKey: "appwin.analytics.test.consent")
    let state = ConsentStore.stored(prefs: prefs, keyPrefix: "appwin.analytics.test.", purpose: .advertising)
    XCTAssertEqual(state, .denied)
    XCTAssertNil(prefs.string(forKey: "appwin.analytics.test.consent"))
    XCTAssertEqual(prefs.string(forKey: "appwin.analytics.test.consent.analytics"), "denied")
  }

  func testWithoutPurposeSetTouchesTheThree() {
    let store = ConsentStore(prefs: InMemoryAnalyticsPrefs(), keyPrefix: "appwin.analytics.test.")
    store.set(.unknown, for: nil)
    XCTAssertTrue(store.anyUnknown)
    store.set(.granted, for: .analytics)
    XCTAssertEqual(store.grantedPurposes, [.analytics])
  }

  func testPurposesArePersistedSeparately() {
    let prefs = InMemoryAnalyticsPrefs()
    let store = ConsentStore(prefs: prefs, keyPrefix: "appwin.analytics.test.")
    store.set(.denied, for: .marketing)
    let reloaded = ConsentStore(prefs: prefs, keyPrefix: "appwin.analytics.test.")
    XCTAssertEqual(reloaded.grantedPurposes, [.analytics, .advertising])
    XCTAssertFalse(reloaded.allDenied)
    XCTAssertEqual(prefs.string(forKey: "appwin.analytics.test.consent.analytics"), nil)
    reloaded.set(.denied, for: nil)
    XCTAssertTrue(reloaded.allDenied)
  }

  func testInitialConsentsApplyInOrderSynchronously() {
    let prefs = InMemoryAnalyticsPrefs()
    let store = ConsentStore(
      prefs: prefs, keyPrefix: "appwin.analytics.test.",
      initial: [(.unknown, nil), (.granted, .marketing)])
    XCTAssertEqual(store.state(for: .analytics), .unknown)
    XCTAssertEqual(store.state(for: .marketing), .granted)
    XCTAssertTrue(store.anyUnknown)
  }

  func testLegacyKeyNeverOverwritesAnAnswerAlreadyGiven() {
    let prefs = InMemoryAnalyticsPrefs()
    prefs.set("denied", forKey: "appwin.analytics.test.consent")
    prefs.set("granted", forKey: "appwin.analytics.test.consent.marketing")
    let store = ConsentStore(prefs: prefs, keyPrefix: "appwin.analytics.test.")
    XCTAssertEqual(store.state(for: .marketing), .granted)
    XCTAssertEqual(store.state(for: .analytics), .denied)
    XCTAssertEqual(store.state(for: .advertising), .denied)
    XCTAssertNil(prefs.string(forKey: "appwin.analytics.test.consent"))
  }

  func testAnAnswerWrittenBeforeTheFirstReadSurvivesTheLegacyKey() {
    let prefs = InMemoryAnalyticsPrefs()
    prefs.set("denied", forKey: "appwin.analytics.test.consent")
    ConsentStore.write(prefs: prefs, keyPrefix: "appwin.analytics.test.", .granted, for: .advertising)
    let store = ConsentStore(prefs: prefs, keyPrefix: "appwin.analytics.test.")
    XCTAssertEqual(store.state(for: .advertising), .granted)
    XCTAssertEqual(store.state(for: .analytics), .denied)
  }

  func testTwoStoresOnTheSamePrefsSeeEachOthersWrites() {
    let prefs = InMemoryAnalyticsPrefs()
    let first = ConsentStore(prefs: prefs, keyPrefix: "appwin.analytics.test.")
    let second = ConsentStore(prefs: prefs, keyPrefix: "appwin.analytics.test.")
    first.set(.granted, for: nil)
    second.set(.denied, for: nil)
    XCTAssertTrue(first.allDenied)
  }

  func testConsentsStagedBeforeConfigureAreWrittenInOrderThenForgotten() {
    AppwinCore.resetConsentForTesting()
    AppwinCore.stageConsentForTesting(.unknown, for: nil)
    AppwinCore.stageConsentForTesting(.granted, for: .marketing)
    let prefs = InMemoryAnalyticsPrefs()
    AppwinCore.applyPendingConsent(prefs: prefs, keyPrefix: "appwin.analytics.test.")
    let store = ConsentStore(prefs: prefs, keyPrefix: "appwin.analytics.test.")
    XCTAssertEqual(store.state(for: .analytics), .unknown)
    XCTAssertEqual(store.state(for: .marketing), .granted)
    let other = InMemoryAnalyticsPrefs()
    AppwinCore.applyPendingConsent(prefs: other, keyPrefix: "appwin.analytics.test.")
    XCTAssertNil(other.string(forKey: "appwin.analytics.test.consent.analytics"))
  }
}
