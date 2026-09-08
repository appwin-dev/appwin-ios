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
}
