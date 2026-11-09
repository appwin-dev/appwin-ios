import XCTest
@_spi(Appwin) @testable import AppwinCore

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

  func testReplayConfigDefaultsAndLenientDecoding() throws {
    let v = try verdict(#"""
      {"products":{
        "replay":{"enabled":true,"config":{"sampleRate":0.25,"maskAllImages":false}},
        "analytics":{"enabled":true,"config":"not an object"},
        "community":{"enabled":true}
      }}
      """#)
    XCTAssertEqual(AvailabilityStore.result(for: .replay, in: v), .ready)
    XCTAssertEqual(
      v.products["replay"]?.config,
      AppwinReplayConfig(sampleRate: 0.25, maskAllText: true, maskAllImages: false))
    XCTAssertNil(v.products["analytics"]?.config)
    XCTAssertEqual(AvailabilityStore.result(for: .analytics, in: v), .ready)
    XCTAssertEqual(AppwinReplayConfig(sampleRate: 4).sampleRate, 1)
  }

  /// Off by default: a server that does not mention replay keeps it off.
  func testReplayIsOffWhenAbsent() throws {
    let v = try verdict(#"{"products":{"analytics":{"enabled":true}}}"#)
    XCTAssertEqual(AvailabilityStore.result(for: .replay, in: v), .unavailable(.disabled))
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

  func testPausedProductIsReadyAndCarriesThePause() throws {
    let v = try verdict(#"""
      {"products":{"support":{"enabled":false,"reason":"plan","paused":{"since":"2026-11-15T10:00:00.000Z","title":"On fait une pause","message":"Dites-lui de payer sa facture."}},
                   "community":{"enabled":false,"reason":"plan"}}}
      """#)
    XCTAssertEqual(AvailabilityStore.result(for: .support, in: v), .ready)
    XCTAssertEqual(
      AvailabilityStore.pause(for: .support, in: v),
      AppwinPause(since: "2026-11-15T10:00:00.000Z", title: "On fait une pause", message: "Dites-lui de payer sa facture."))
    XCTAssertEqual(AvailabilityStore.result(for: .community, in: v), .unavailable(.plan))
    XCTAssertNil(AvailabilityStore.pause(for: .community, in: v))
  }

  func testPauseWithoutTextIsAPauseWithEmptyStrings() throws {
    let v = try verdict(#"{"products":{"support":{"enabled":false,"reason":"plan","paused":{"since":"2026-11-15T10:00:00.000Z"}}}}"#)
    XCTAssertEqual(AvailabilityStore.result(for: .support, in: v), .ready)
    XCTAssertEqual(AvailabilityStore.pause(for: .support, in: v)?.title, "")
  }

  func testMalformedPauseCountsAsOutOfPlan() throws {
    let v = try verdict(#"{"products":{"support":{"enabled":false,"reason":"plan","paused":"yes"}}}"#)
    XCTAssertEqual(AvailabilityStore.result(for: .support, in: v), .unavailable(.plan))
    XCTAssertNil(AvailabilityStore.pause(for: .support, in: v))
  }

  func testCachedVerdictWrittenBeforeThePauseStillDecodes() throws {
    let v = try verdict(#"{"products":{"support":{"enabled":true}}}"#)
    XCTAssertEqual(AvailabilityStore.result(for: .support, in: v), .ready)
    XCTAssertNil(AvailabilityStore.pause(for: .support, in: v))
  }

  func testPauseUpdatesEmitWhenOnlyThePauseChanges() async throws {
    var results = AvailabilityUpdates.stream(of: .support, store: nil).makeAsyncIterator()
    var pauses = AvailabilityUpdates.pauseStream(of: .support, store: nil).makeAsyncIterator()
    _ = await results.next()  // .notConfigured
    _ = await pauses.next()   // nil
    AvailabilityUpdates.publish(try verdict(#"{"products":{"support":{"enabled":true}}}"#))
    let ready = await results.next()
    XCTAssertEqual(ready, .ready)
    let none = await pauses.next()
    XCTAssertNil(none ?? nil)
    AvailabilityUpdates.publish(try verdict(#"{"products":{"support":{"enabled":false,"reason":"plan","paused":{"since":"2026-11-15T10:00:00.000Z","title":"T","message":"M"}}}}"#))
    let paused = await pauses.next()
    XCTAssertEqual(paused ?? nil, AppwinPause(since: "2026-11-15T10:00:00.000Z", title: "T", message: "M"))
  }

  func testAvailabilityRequestSaysTheDeviceLanguage() async throws {
    let seen = Captured()
    let client = ClientApi(baseUrl: "http://localhost", headersProvider: { [:] }, dataFor: { request in
      await seen.set(request.value(forHTTPHeaderField: "X-Appwin-Language"))
      return (Data(#"{"products":{}}"#.utf8), HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!)
    })
    _ = await AvailabilityStore(appId: "lang-test").fetch(client: client)
    let header = await seen.value
    XCTAssertEqual(header, AvailabilityStore.languageHeader()["X-Appwin-Language"])
  }

  func testLanguageHeaderKeepsTheLanguageOfTheFirstPreferred() {
    XCTAssertEqual(AvailabilityStore.languageHeader(preferred: ["fr-CA", "en"]), ["X-Appwin-Language": "fr"])
    XCTAssertEqual(AvailabilityStore.languageHeader(preferred: ["EN-us"]), ["X-Appwin-Language": "en"])
    XCTAssertEqual(AvailabilityStore.languageHeader(preferred: []), [:])
  }
}

private actor Captured {
  var value: String?
  func set(_ v: String?) { value = v }
}
