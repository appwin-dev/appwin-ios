import XCTest
@testable import AppwinCore

final class AppwinCoreTests: XCTestCase {
  /// `@MainActor` because the SDK is: `AppwinCore` is a MainActor-isolated
  /// `enum`, and under strict concurrency an assertion cannot read its state
  /// from a non-isolated context.
  @MainActor
  func testVersionIsSet() {
    XCTAssertFalse(AppwinCore.version.isEmpty)
  }

  @MainActor
  func testConfigureStartsTheEventPipelineOnce() {
    AppwinCore.configure(projectAppId: "app-test")
    let first = AppwinCore.analyticsPipeline
    XCTAssertNotNil(first)
    AppwinCore.configure(projectAppId: "app-test")
    XCTAssertTrue(AppwinCore.analyticsPipeline === first)
  }
}
