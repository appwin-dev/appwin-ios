import XCTest
@testable import AppwinCore

final class BackoffTests: XCTestCase {

  // Double.random(in:using:) maps a constant stream near the upper bound;
  // asserting on ranges keeps the test independent from that mapping.
  func testDelaysDoubleUpToTheCap() {
    let backoff = Backoff(base: 2, cap: 300)
    var generator = SystemRandomNumberGenerator()
    let expectations: [(attempt: Int, raw: Double)] = [
      (0, 2), (1, 4), (2, 8), (7, 256), (8, 300), (50, 300),
    ]
    for (attempt, raw) in expectations {
      let delay = backoff.delay(attempt: attempt, using: &generator)
      XCTAssertGreaterThanOrEqual(delay, raw * 0.5, "attempt \(attempt)")
      XCTAssertLessThanOrEqual(delay, raw, "attempt \(attempt)")
    }
  }

  func testJitterStaysInUpperHalfOfRawDelay() {
    let backoff = Backoff(base: 2, cap: 300)
    for _ in 0..<1_000 {
      let delay = backoff.delay(attempt: 3)
      XCTAssertGreaterThanOrEqual(delay, 8)
      XCTAssertLessThanOrEqual(delay, 16)
    }
  }

  func testHugeAttemptCountDoesNotOverflow() {
    let backoff = Backoff(base: 2, cap: 300)
    let delay = backoff.delay(attempt: Int.max)
    XCTAssertGreaterThanOrEqual(delay, 150)
    XCTAssertLessThanOrEqual(delay, 300)
  }
}
