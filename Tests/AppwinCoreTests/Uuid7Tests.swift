import XCTest
@testable import AppwinCore

// Deterministic generator for jitter-free assertions.
struct SeededGenerator: RandomNumberGenerator {
  var state: UInt64
  mutating func next() -> UInt64 {
    state = state &* 6364136223846793005 &+ 1442695040888963407
    return state
  }
}

final class Uuid7Tests: XCTestCase {

  func testFormatIsLowercaseUuidWithVersion7AndVariant10() {
    let uuid = Uuid7.generate()
    let pattern = "^[0-9a-f]{8}-[0-9a-f]{4}-7[0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$"
    XCTAssertNotNil(uuid.range(of: pattern, options: .regularExpression), uuid)
  }

  func testTimestampMsIsEmbeddedInFirst48Bits() {
    let nowMs: UInt64 = 1_788_500_000_123
    var generator = SeededGenerator(state: 42)
    let uuid = Uuid7.generate(now: Date(timeIntervalSince1970: Double(nowMs) / 1000), using: &generator)
    XCTAssertEqual(Uuid7.timestampMs(of: uuid), nowMs)
  }

  func testIncreasingInstantsSortLexically() {
    var generator = SeededGenerator(state: 1)
    let a = Uuid7.generate(now: Date(timeIntervalSince1970: 1), using: &generator)
    let b = Uuid7.generate(now: Date(timeIntervalSince1970: 2), using: &generator)
    XCTAssertLessThan(a, b)
  }

  func testTenThousandGenerationsAreUnique() {
    var seen = Set<String>()
    for _ in 0..<10_000 { seen.insert(Uuid7.generate()) }
    XCTAssertEqual(seen.count, 10_000)
  }

  func testTimestampMsRejectsNonUuidStrings() {
    XCTAssertNil(Uuid7.timestampMs(of: "not-a-uuid"))
    XCTAssertNil(Uuid7.timestampMs(of: String(repeating: "zz", count: 16)))
  }
}
