import XCTest
import os
@_spi(Appwin) @testable import AppwinCore

/// Core's own bus follows the consent set through `AppwinCore.setConsent`,
/// the instant it is set.
final class ConsentRoutingTests: XCTestCase {
  override func setUp() {
    super.setUp()
    AppwinCore.resetConsentForTesting()
  }

  override func tearDown() {
    AppwinCore.resetConsentForTesting()
    super.tearDown()
  }

  func testCoreBusFollowsThePurposeJustDenied() {
    let seen = OSAllocatedUnfairLock<[String]>(initialState: [])
    let ads = AppwinCore.eventBus.subscribe(purpose: .advertising) { _ in seen.withLock { $0.append("ads") } }
    let skan = AppwinCore.eventBus.subscribe(purpose: nil) { _ in seen.withLock { $0.append("skan") } }
    let crashes = AppwinCore.eventBus.subscribe(purpose: .analytics) { _ in seen.withLock { $0.append("crash") } }

    AppwinCore.setConsent(.denied, for: .advertising)
    AppwinCore.eventBus.publish(EventBus.Event(name: "purchase", eventId: "e1", props: nil))
    XCTAssertEqual(seen.withLock { $0 }.sorted(), ["crash", "skan"])

    AppwinCore.setConsent(.denied)
    seen.withLock { $0 = [] }
    AppwinCore.eventBus.publish(EventBus.Event(name: "purchase", eventId: "e2", props: nil))
    XCTAssertEqual(seen.withLock { $0 }, ["skan"])
    withExtendedLifetime((ads, skan, crashes)) {}
  }

  func testConsentStateReadsWhatWasJustSet() {
    AppwinCore.setConsent(.unknown, for: .marketing)
    XCTAssertEqual(AppwinCore.consentState(for: .marketing), .unknown)
    XCTAssertEqual(AppwinCore.consentState(for: .analytics), .granted)
  }

  @MainActor
  func testTwoQuickCallsEndWithStoreBusAndPipelineAllDenied() async throws {
    AppwinCore.configure(projectAppId: "app-test")
    let seen = OSAllocatedUnfairLock<Int>(initialState: 0)
    let crashes = AppwinCore.eventBus.subscribe(purpose: .analytics) { _ in seen.withLock { $0 += 1 } }
    AppwinCore.setConsent(.granted)
    AppwinCore.setConsent(.denied)
    for purpose in ConsentPurpose.allCases {
      XCTAssertEqual(AppwinCore.consentState(for: purpose), .denied)
    }
    AppwinCore.eventBus.publish(EventBus.Event(name: "purchase", eventId: "e1", props: nil))
    XCTAssertEqual(seen.withLock { $0 }, 0)
    let pipeline = try XCTUnwrap(AppwinCore.analyticsPipeline)
    try await Task.sleep(nanoseconds: 200_000_000)
    let queued = await pipeline.queuedEventCount()
    XCTAssertEqual(queued, 0)
    XCTAssertEqual(
      UserDefaults.standard.string(forKey: "appwin.analytics.app-test.consent.marketing"), "denied")
    withExtendedLifetime(crashes) {}
  }
}
