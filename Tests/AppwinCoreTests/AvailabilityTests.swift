import XCTest
@testable import AppwinCore

@MainActor
final class AvailabilityTests: XCTestCase {

  override func setUp() {
    super.setUp()
    AvailabilityUpdates.reset()
  }

  private func verdict(_ json: String) throws -> AvailabilityVerdict {
    try JSONDecoder().decode(AvailabilityVerdict.self, from: Data(json.utf8))
  }

  func testDebugOnlyVerdictOpensTheProductAndIsFlagged() throws {
    let v = try verdict(#"{"products":{"community":{"enabled":true,"debugOnly":true}}}"#)
    XCTAssertEqual(AvailabilityStore.result(for: .community, in: v), .ready)
    XCTAssertTrue(AvailabilityStore.isDebugOnly(.community, in: v))
  }

  /// Servers older than the debug unlock omit the field.
  func testVerdictWithoutDebugOnlyStillDecodes() throws {
    let v = try verdict(#"{"products":{"community":{"enabled":false,"reason":"plan"}}}"#)
    XCTAssertEqual(AvailabilityStore.result(for: .community, in: v), .unavailable(.plan))
    XCTAssertFalse(AvailabilityStore.isDebugOnly(.community, in: v))
    XCTAssertEqual(AvailabilityStore.result(for: .support, in: v), .unavailable(.disabled))
  }

  func testUpdatesEmitOnlyChangesAndIgnoreALaterUnknown() async throws {
    var iterator = AvailabilityUpdates.stream(of: .community, store: nil).makeAsyncIterator()
    // Not configured: the subscriber learns it straight away.
    let first = await iterator.next()
    XCTAssertEqual(first, .notConfigured)

    let off = try verdict(#"{"products":{"community":{"enabled":false,"reason":"disabled"}}}"#)
    let on = try verdict(#"{"products":{"community":{"enabled":true}}}"#)
    AvailabilityUpdates.publish(off)
    let second = await iterator.next()
    XCTAssertEqual(second, .unavailable(.disabled))

    // A failed request with nothing cached must not replace a known verdict.
    AvailabilityUpdates.publish(nil)
    var late = AvailabilityUpdates.stream(of: .community, store: nil).makeAsyncIterator()
    let replayed = await late.next()
    XCTAssertEqual(replayed, .unavailable(.disabled))

    AvailabilityUpdates.publish(on)
    let third = await iterator.next()
    XCTAssertEqual(third, .ready)
  }
}
