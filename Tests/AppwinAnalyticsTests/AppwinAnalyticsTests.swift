import XCTest
@testable import AppwinAnalytics

final class AppwinAnalyticsTests: XCTestCase {
  // The façade delegates to Core, whose pipeline has its own suite. What this
  // target guarantees is the product contract: calling it before `configure`
  // must be a silent no-op, never a crash.
  func testCallsBeforeConfigureNeverCrash() {
    AppwinAnalytics.track("some_event", props: ["plan": "pro"])
    AppwinAnalytics.screen("home")
    AppwinAnalytics.flush()
    AppwinAnalytics.setConsent(.granted)
  }
}
