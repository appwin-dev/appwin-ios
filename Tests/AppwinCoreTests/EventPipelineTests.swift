import XCTest
@_spi(Appwin) @testable import AppwinCore

/// Scripted sender: pops one outcome per call, then answers `.ok`.
private actor FakeSender: EventSender {
  private(set) var batches: [[String]] = []
  private var script: [SendOutcome]

  init(script: [SendOutcome] = []) { self.script = script }

  func send(lines: [String]) async -> SendOutcome {
    batches.append(lines)
    return script.isEmpty ? .ok : script.removeFirst()
  }
}

private final class ClockBox: @unchecked Sendable {
  private let lock = NSLock()
  private var value = Date(timeIntervalSince1970: 1_788_500_000)

  var now: Date {
    lock.lock()
    defer { lock.unlock() }
    return value
  }

  func advance(by seconds: TimeInterval) {
    lock.lock()
    defer { lock.unlock() }
    value = value.addingTimeInterval(seconds)
  }
}

private final class ReauthorizeFlag: @unchecked Sendable {
  private let lock = NSLock()
  private(set) var calls = 0
  var result = true

  func record() -> Bool {
    lock.lock()
    defer { lock.unlock() }
    calls += 1
    return result
  }
}

final class EventPipelineTests: XCTestCase {
  private var directory: URL!
  private var prefs: InMemoryAnalyticsPrefs!
  private var clock: ClockBox!
  private var reauthorize: ReauthorizeFlag!

  override func setUp() {
    super.setUp()
    directory = FileManager.default.temporaryDirectory
      .appendingPathComponent("appwin-pipeline-tests-\(UUID().uuidString)")
    prefs = InMemoryAnalyticsPrefs()
    clock = ClockBox()
    reauthorize = ReauthorizeFlag()
  }

  override func tearDown() {
    try? FileManager.default.removeItem(at: directory)
    super.tearDown()
  }

  private func makePipeline(
    sender: FakeSender,
    consent: ConsentState? = .granted,
    maxBatch: Int = 500
  ) -> EventPipeline {
    var config = AnalyticsConfig()
    config.maxBatch = maxBatch
    config.backoffBase = 0.02
    config.backoffCap = 0.02
    let keyPrefix = "appwin.analytics.test."
    // Explicit even for the granted default: the tests must not depend on it.
    let consentStore = ConsentStore(prefs: prefs, keyPrefix: keyPrefix)
    if let consent { consentStore.set(consent, for: nil) }
    let clock = self.clock!
    let reauthorize = self.reauthorize!
    return EventPipeline(
      store: EventStore(directory: directory, maxBatch: maxBatch, maxQueueEvents: config.maxQueueEvents),
      sessions: SessionManager(
        prefs: prefs, keyPrefix: keyPrefix, appVersion: "1.0.0",
        timeout: config.sessionTimeout, maxAge: config.maxSessionAge, now: { clock.now }),
      consentStore: consentStore,
      sender: sender,
      config: config,
      prefs: prefs,
      keyPrefix: keyPrefix,
      reauthorize: { reauthorize.record() },
      now: { clock.now })
  }

  private func waitUntil(
    timeout: TimeInterval = 3, _ condition: @escaping () async -> Bool
  ) async throws {
    let deadline = Date().addingTimeInterval(timeout)
    while Date() < deadline {
      if await condition() { return }
      try await Task.sleep(nanoseconds: 20_000_000)
    }
    XCTFail("condition not met within \(timeout)s")
  }

  private func purposes(of lines: [String]) -> [[String]] {
    lines.map { line in
      let object = try? JSONSerialization.jsonObject(with: Data(line.utf8)) as? [String: Any]
      return object?["purposes"] as? [String] ?? []
    }
  }

  func testEverySentLineCarriesTheGrantedPurposes() async throws {
    let sender = FakeSender()
    let pipeline = makePipeline(sender: sender)
    await pipeline.enqueue(name: "purchase", screen: nil, props: ["plan": "pro"], occurredAt: clock.now)
    await pipeline.flushNow()
    try await waitUntil { await sender.batches.count == 1 }
    let stamped = purposes(of: await sender.batches[0])
    XCTAssertEqual(stamped, Array(repeating: ["analytics", "marketing", "advertising"], count: 3))
    let queued = await pipeline.queuedEventCount()
    XCTAssertEqual(queued, 0)
  }

  func testMarketingDeniedSendsWithTheTwoOtherPurposes() async throws {
    let sender = FakeSender()
    let pipeline = makePipeline(sender: sender)
    await pipeline.setConsent(.denied, for: .marketing)
    await pipeline.enqueue(name: "purchase", screen: nil, props: nil, occurredAt: clock.now)
    await pipeline.flushNow()
    try await waitUntil { await sender.batches.count == 1 }
    let first = await sender.batches[0]
    XCTAssertEqual(purposes(of: first).last, ["analytics", "advertising"])
  }

  func testAllPurposesDeniedPurgesAndSendsNothing() async throws {
    let sender = FakeSender()
    let pipeline = makePipeline(sender: sender)
    await pipeline.enqueue(name: "purchase", screen: nil, props: nil, occurredAt: clock.now)
    await pipeline.setConsent(.denied, for: nil)
    await pipeline.flushNow()
    try await Task.sleep(nanoseconds: 100_000_000)
    let queued = await pipeline.queuedEventCount()
    XCTAssertEqual(queued, 0)
    let sent = await sender.batches.count
    XCTAssertEqual(sent, 0)
    XCTAssertEqual(prefs.string(forKey: "appwin.analytics.test.installTracked"), "1")
  }

  func testNothingIsEnqueuedOrSentWhileAllDeniedEvenOnForeground() async throws {
    let sender = FakeSender()
    let pipeline = makePipeline(sender: sender, consent: .denied)
    await pipeline.onForeground()
    await pipeline.enqueue(name: "purchase", screen: nil, props: nil, occurredAt: clock.now)
    await pipeline.onBackground()
    try await Task.sleep(nanoseconds: 100_000_000)
    let queued = await pipeline.queuedEventCount()
    XCTAssertEqual(queued, 0)
    let sent = await sender.batches.count
    XCTAssertEqual(sent, 0)
  }

  func testGrantingAgainAfterAllDeniedDoesNotEmitAppInstallAgain() async throws {
    let sender = FakeSender()
    let pipeline = makePipeline(sender: sender)
    await pipeline.enqueue(name: "purchase", screen: nil, props: nil, occurredAt: clock.now)
    await pipeline.setConsent(.denied, for: nil)
    await pipeline.setConsent(.granted, for: nil)
    await pipeline.enqueue(name: "again", screen: nil, props: nil, occurredAt: clock.now)
    await pipeline.flushNow()
    try await waitUntil { await sender.batches.count == 1 }
    let names = (await sender.batches[0]).compactMap { line -> String? in
      (try? JSONSerialization.jsonObject(with: Data(line.utf8)) as? [String: Any])?["name"] as? String
    }
    XCTAssertFalse(names.contains("app_install"))
    XCTAssertTrue(names.contains("again"))
  }

  func testOneUnknownPurposeHoldsTheBacklogUntilAnswered() async throws {
    let sender = FakeSender()
    let pipeline = makePipeline(sender: sender)
    await pipeline.setConsent(.unknown, for: .advertising)
    await pipeline.enqueue(name: "purchase", screen: nil, props: nil, occurredAt: clock.now)
    await pipeline.flushNow()
    try await Task.sleep(nanoseconds: 100_000_000)
    let held = await sender.batches.count
    XCTAssertEqual(held, 0)
    await pipeline.setConsent(.granted, for: .advertising)
    try await waitUntil { await sender.batches.count == 1 }
    let first = await sender.batches[0]
    XCTAssertEqual(purposes(of: first).last, ["analytics", "marketing", "advertising"])
  }

  func testBacklogHeldUnderUnknownGoesWithThePurposesGrantedAtAnswerTime() async throws {
    let sender = FakeSender()
    let pipeline = makePipeline(sender: sender)
    await pipeline.setConsent(.unknown, for: nil)
    await pipeline.enqueue(name: "purchase", screen: nil, props: nil, occurredAt: clock.now)
    await pipeline.setConsent(.denied, for: .marketing)
    await pipeline.setConsent(.granted, for: .analytics)
    await pipeline.setConsent(.granted, for: .advertising)
    try await waitUntil { await sender.batches.count == 1 }
    let first = await sender.batches[0]
    XCTAssertEqual(purposes(of: first).last, ["analytics", "advertising"])
  }

  func testConsentSignalsReachingTheActorOutOfOrderAllSeeTheLastWrite() async throws {
    let sender = FakeSender()
    let pipeline = makePipeline(sender: sender)
    await pipeline.enqueue(name: "purchase", screen: nil, props: nil, occurredAt: clock.now)
    // Two quick `AppwinCore.setConsent` calls: both writes are already in the
    // store when their (unordered) signals arrive.
    let writer = ConsentStore(prefs: prefs, keyPrefix: "appwin.analytics.test.")
    writer.set(.granted, for: nil)
    writer.set(.denied, for: nil)
    await pipeline.consentChanged()
    await pipeline.consentChanged()
    await pipeline.flushNow()
    try await Task.sleep(nanoseconds: 100_000_000)
    let queued = await pipeline.queuedEventCount()
    XCTAssertEqual(queued, 0)
    let sent = await sender.batches.count
    XCTAssertEqual(sent, 0)
    XCTAssertTrue(ConsentStore(prefs: prefs, keyPrefix: "appwin.analytics.test.").allDenied)
  }

  func testAnUnknownAnswerPersistedByAPreviousRunStillHoldsTheBacklog() async throws {
    ConsentStore(prefs: prefs, keyPrefix: "appwin.analytics.test.").set(.unknown, for: .marketing)
    let sender = FakeSender()
    let relaunched = makePipeline(sender: sender, consent: nil)
    await relaunched.enqueue(name: "purchase", screen: nil, props: nil, occurredAt: clock.now)
    await relaunched.flushNow()
    try await Task.sleep(nanoseconds: 100_000_000)
    let held = await sender.batches.count
    XCTAssertEqual(held, 0)
    await relaunched.setConsent(.granted, for: .marketing)
    try await waitUntil { await sender.batches.count == 1 }
  }

  func testSuccessfulFlushSendsSessionEventsThenCustomAndEmptiesQueue() async throws {
    let sender = FakeSender()
    let pipeline = makePipeline(sender: sender)
    await pipeline.enqueue(name: "spot_saved", screen: nil, props: ["plan": "pro"], occurredAt: clock.now)
    await pipeline.flushNow()
    try await waitUntil { await sender.batches.count == 1 }
    let names = await sender.batches[0].compactMap { line -> String? in
      let object = try? JSONSerialization.jsonObject(with: Data(line.utf8)) as? [String: Any]
      return object?["name"] as? String
    }
    XCTAssertEqual(names, ["app_install", "session_start", "spot_saved"])
    let queued = await pipeline.queuedEventCount()
    XCTAssertEqual(queued, 0)
  }

  func testQuotaExceededDeletesBatchAndCoolsDown() async throws {
    let sender = FakeSender(script: [.quotaExceeded])
    let pipeline = makePipeline(sender: sender)
    await pipeline.enqueue(name: "spot_saved", screen: nil, props: nil, occurredAt: clock.now)
    await pipeline.flushNow()
    try await waitUntil { await pipeline.queuedEventCount() == 0 }

    await pipeline.enqueue(name: "spot_saved", screen: nil, props: nil, occurredAt: clock.now)
    await pipeline.flushNow()
    try await Task.sleep(nanoseconds: 100_000_000)
    let callsDuringCooldown = await sender.batches.count
    XCTAssertEqual(callsDuringCooldown, 1, "cooldown must block the second flush")

    clock.advance(by: 61 * 60)
    await pipeline.flushNow()
    try await waitUntil { await sender.batches.count == 2 }
  }

  func testFatalDropsTheBatchAndMovesOn() async throws {
    let sender = FakeSender(script: [.fatal])
    let pipeline = makePipeline(sender: sender, maxBatch: 2)
    for i in 1...4 {
      await pipeline.enqueue(name: "event_\(i)", screen: nil, props: nil, occurredAt: clock.now)
    }
    await pipeline.flushNow()
    try await waitUntil { await pipeline.queuedEventCount() == 0 }
    let calls = await sender.batches.count
    XCTAssertGreaterThanOrEqual(calls, 2, "the fatal batch is dropped, the rest still goes out")
    XCTAssertEqual(prefs.string(forKey: "appwin.analytics.test.droppedCount"), "2")
  }

  func testUnauthorizedReauthorizesOnceAndRetriesTheSameBatch() async throws {
    let sender = FakeSender(script: [.unauthorized])
    let pipeline = makePipeline(sender: sender)
    await pipeline.enqueue(name: "spot_saved", screen: nil, props: nil, occurredAt: clock.now)
    await pipeline.flushNow()
    try await waitUntil { await pipeline.queuedEventCount() == 0 }
    XCTAssertEqual(reauthorize.calls, 1)
    let batches = await sender.batches
    XCTAssertEqual(batches.count, 2)
    XCTAssertEqual(batches[0], batches[1])
  }

  func testRetryableKeepsTheBatchAndRetriesAfterBackoff() async throws {
    let sender = FakeSender(script: [.retryable])
    let pipeline = makePipeline(sender: sender)
    await pipeline.enqueue(name: "spot_saved", screen: nil, props: nil, occurredAt: clock.now)
    await pipeline.flushNow()
    try await waitUntil { await sender.batches.count == 2 }
    try await waitUntil { await pipeline.queuedEventCount() == 0 }
    XCTAssertEqual(reauthorize.calls, 0)
  }

  func testUnknownConsentQueuesButNeverSends() async throws {
    let sender = FakeSender()
    let pipeline = makePipeline(sender: sender, consent: .unknown)
    await pipeline.enqueue(name: "spot_saved", screen: nil, props: nil, occurredAt: clock.now)
    await pipeline.flushNow()
    try await Task.sleep(nanoseconds: 100_000_000)
    let calls = await sender.batches.count
    XCTAssertEqual(calls, 0)
    let queued = await pipeline.queuedEventCount()
    XCTAssertEqual(queued, 3, "install + session_start + custom are all waiting")
  }

  func testGrantingConsentFlushesTheBacklog() async throws {
    let sender = FakeSender()
    let pipeline = makePipeline(sender: sender, consent: .unknown)
    await pipeline.enqueue(name: "spot_saved", screen: nil, props: nil, occurredAt: clock.now)
    await pipeline.flushNow()
    await pipeline.setConsent(.granted, for: nil)
    try await waitUntil { await pipeline.queuedEventCount() == 0 }
    let calls = await sender.batches.count
    XCTAssertEqual(calls, 1)
  }

  func testDenyingConsentPurgesAndMutesEverything() async throws {
    let sender = FakeSender()
    let pipeline = makePipeline(sender: sender, consent: .unknown)
    await pipeline.enqueue(name: "spot_saved", screen: nil, props: nil, occurredAt: clock.now)
    await pipeline.setConsent(.denied, for: nil)
    let queuedAfterPurge = await pipeline.queuedEventCount()
    XCTAssertEqual(queuedAfterPurge, 0)
    await pipeline.enqueue(name: "spot_saved", screen: nil, props: nil, occurredAt: clock.now)
    await pipeline.flushNow()
    try await Task.sleep(nanoseconds: 100_000_000)
    let calls = await sender.batches.count
    XCTAssertEqual(calls, 0)
    let queued = await pipeline.queuedEventCount()
    XCTAssertEqual(queued, 0)
  }

  func testForegroundEmitsAppOpenOncePerForegroundAndBackgroundEmitsAppBackground() async throws {
    let sender = FakeSender()
    let pipeline = makePipeline(sender: sender)
    await pipeline.onForeground()
    await pipeline.onForeground()
    await pipeline.onBackground()
    try await waitUntil { await sender.batches.flatMap { $0 }.count == 4 }
    let names = await sender.batches.flatMap { $0 }.compactMap { line -> String? in
      let object = try? JSONSerialization.jsonObject(with: Data(line.utf8)) as? [String: Any]
      return object?["name"] as? String
    }
    XCTAssertEqual(names, ["app_install", "session_start", "app_open", "app_background"])
  }

  func testAutomaticEventsBypassTheReservedNameCheck() async throws {
    let sender = FakeSender()
    let pipeline = makePipeline(sender: sender)
    await pipeline.enqueueAutomatic(name: "push_opened", props: ["delivery_id": "d1"], occurredAt: clock.now)
    await pipeline.flushNow()
    try await waitUntil { await sender.batches.count == 1 }
    let batch = await sender.batches[0]
    let last = try XCTUnwrap(batch.last)
    XCTAssertTrue(last.contains("\"name\":\"push_opened\""))
    XCTAssertTrue(last.contains("\"delivery_id\":\"d1\""))
  }

  func testTheLifecycleNamesAreReservedForTrack() {
    for name in ["app_open", "app_background", "push_opt_in", "push_opened"] {
      XCTAssertTrue(AnalyticsValidation.reservedNames.contains(name), name)
    }
  }
}
