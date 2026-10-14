import XCTest
@_spi(Appwin) @testable import AppwinCore

private actor FakeCrashSender: CrashSender {
  private(set) var batches: [[String]] = []

  func send(reports: [String]) async -> SendOutcome {
    batches.append(reports)
    return .ok
  }
}

private final class ConsentBox: @unchecked Sendable {
  private let lock = NSLock()
  private var value: AnalyticsConsent

  init(_ value: AnalyticsConsent) { self.value = value }

  var consent: AnalyticsConsent {
    lock.lock()
    defer { lock.unlock() }
    return value
  }
}

private enum SyncError: Error {
  case offline
  case rejected(email: String)
}

private struct ValidationError: Error {
  let field: String
}

final class CrashReporterTests: XCTestCase {
  private var directory: URL!

  override func setUp() {
    super.setUp()
    directory = FileManager.default.temporaryDirectory
      .appendingPathComponent("appwin-crash-tests-\(UUID().uuidString)")
  }

  override func tearDown() {
    AppwinCore.setCrashReporterForTesting(nil)
    ExceptionCrashHandler.uninstallForTesting()
    try? FileManager.default.removeItem(at: directory)
    super.tearDown()
  }

  private let context = CrashContext(
    appVersion: "2.1.0", appBuild: "42", os: "iOS 18.1", model: "iPhone16,2", sdkVersion: "0.9.2")

  private func makeReporter(
    consent: AnalyticsConsent, sender: FakeCrashSender = FakeCrashSender()
  ) -> CrashReporter {
    let box = ConsentBox(consent)
    return CrashReporter(
      store: CrashStore(directory: directory),
      sender: sender,
      context: context,
      inApp: InAppModules([]),
      signalDirectory: nil,
      storedConsent: { box.consent },
      sessionId: { "0192b3c4-0000-7000-8000-000000000001" },
      reauthorize: { true })
  }

  private func storedReports(_ reporter: CrashReporter) -> [[String: Any]] {
    reporter.store.pending(limit: 100).compactMap {
      try? JSONSerialization.jsonObject(with: Data($0.json.utf8)) as? [String: Any]
    }
  }

  // MARK: - Wire format

  func testJSONMatchesTheContract() throws {
    let report = CrashReport(
      crashId: "8a6e0f2c-1111-4222-8333-444455556666",
      kind: .nonFatal,
      runtime: "ios",
      occurredAt: Date(timeIntervalSince1970: 1_788_500_000),
      sessionId: "0192b3c4-0000-7000-8000-000000000001",
      screen: "checkout",
      exceptionType: "NSURLErrorDomain(-1009)",
      exceptionMessage: String(repeating: "m", count: 2000),
      frames: [CrashReport.Frame(fn: "main", line: 3, module: "App", addr: 0x1000, inApp: true)],
      context: context,
      breadcrumbs: [.init(at: Date(timeIntervalSince1970: 1_788_499_999), type: .screen, name: "checkout")],
      debugImages: [BinaryImage(name: "App", addr: 0x1000, size: 0x200, debugId: "abc", isMainExecutable: true)])
    let data = try XCTUnwrap(report.jsonData())
    let json = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])

    XCTAssertEqual(
      Set(json.keys),
      ["crashId", "kind", "runtime", "occurredAt", "sessionId", "screen", "exception", "frames",
       "app", "device", "sdkVersion", "breadcrumbs", "debugImages"])
    XCTAssertEqual(json["kind"] as? String, "non_fatal")
    XCTAssertEqual(json["runtime"] as? String, "ios")
    XCTAssertEqual(json["occurredAt"] as? String, "2026-09-04T05:33:20.000Z")
    let exception = try XCTUnwrap(json["exception"] as? [String: Any])
    XCTAssertEqual(exception["type"] as? String, "NSURLErrorDomain(-1009)")
    XCTAssertEqual((exception["message"] as? String)?.count, 1024)
    let frame = try XCTUnwrap((json["frames"] as? [[String: Any]])?.first)
    XCTAssertEqual(Set(frame.keys), ["fn", "line", "module", "addr", "inApp"])
    XCTAssertEqual(frame["addr"] as? String, "0x1000")
    XCTAssertEqual(json["app"] as? [String: String], ["version": "2.1.0", "build": "42"])
    XCTAssertEqual(json["device"] as? [String: String], ["os": "iOS 18.1", "model": "iPhone16,2"])
    let crumb = try XCTUnwrap((json["breadcrumbs"] as? [[String: Any]])?.first)
    XCTAssertEqual(Set(crumb.keys), ["at", "type", "name"])
    let image = try XCTUnwrap((json["debugImages"] as? [[String: Any]])?.first)
    XCTAssertEqual(Set(image.keys), ["debugId", "name", "addr", "size"])
    XCTAssertEqual(image["addr"] as? String, "0x1000")
  }

  func testCurrentContextUsesTheEventsOSFormat() {
    let current = CrashContext.current(sdkVersion: "0.9.2")
    XCTAssertTrue(current.os.hasPrefix("iOS "), current.os)
    XCTAssertFalse(current.model.isEmpty)
  }

  // MARK: - Store

  func testStoreKeepsTheNewestReportsAndLeavesNoTempFile() throws {
    let store = CrashStore(directory: directory, maxReports: 3)
    for index in 1...5 {
      XCTAssertTrue(store.write(crashId: "crash-\(index)", json: Data("{\"n\":\(index)}".utf8)))
    }
    let pending = store.pending(limit: 10)
    XCTAssertEqual(pending.map(\.json), ["{\"n\":3}", "{\"n\":4}", "{\"n\":5}"])
    let names = try FileManager.default.contentsOfDirectory(atPath: directory.path)
    XCTAssertFalse(names.contains { $0.hasSuffix(".tmp") })
  }

  // MARK: - Consent

  func testDeniedCapturesNothing() {
    let reporter = makeReporter(consent: .denied)
    reporter.recordBridged(runtime: "flutter", fatal: true, type: "StateError", message: nil, frames: [])
    XCTAssertEqual(reporter.store.count(), 0)
  }

  func testDeniedPurgesTheBacklog() async throws {
    let reporter = makeReporter(consent: .unknown)
    reporter.recordBridged(runtime: "flutter", fatal: true, type: "StateError", message: nil, frames: [])
    XCTAssertEqual(reporter.store.count(), 1)
    reporter.onConsentChanged(.denied)
    for _ in 0..<50 where FileManager.default.fileExists(atPath: directory.path) {
      try await Task.sleep(nanoseconds: 10_000_000)
    }
    XCTAssertEqual(reporter.store.count(), 0)
  }

  func testUnknownStoresButNeverSends() async {
    let sender = FakeCrashSender()
    let reporter = makeReporter(consent: .unknown, sender: sender)
    reporter.recordBridged(runtime: "react_native", fatal: false, type: "TypeError", message: "x", frames: [])
    await reporter.flushNow()
    let batches = await sender.batches
    XCTAssertTrue(batches.isEmpty)
    XCTAssertEqual(reporter.store.count(), 1)
  }

  func testGrantedSendsAndDeletes() async {
    let sender = FakeCrashSender()
    let reporter = makeReporter(consent: .unknown, sender: sender)
    reporter.recordBridged(runtime: "react_native", fatal: false, type: "TypeError", message: "x", frames: [])
    reporter.onConsentChanged(.granted)
    await reporter.flushNow()
    let batches = await sender.batches
    XCTAssertEqual(batches.flatMap { $0 }.count, 1)
    XCTAssertEqual(reporter.store.count(), 0)
  }

  // MARK: - Capture

  func testBridgedErrorIsOnDiskWhenTheCallReturns() throws {
    let reporter = makeReporter(consent: .unknown)
    AppwinCore.setCrashReporterForTesting(reporter)
    reporter.onScreen("cart")
    reporter.onEvent("add_to_cart")
    AppwinCore.recordBridgedError(
      runtime: "react_native", fatal: true, type: "TypeError", message: "undefined is not a function",
      frames: [
        ["fn": "onPress", "file": "app.bundle", "line": 12, "col": NSNumber(value: 4.0), "inApp": true],
        ["fn": "invoke", "module": "react-native", "inApp": false],
      ])
    AppwinCore.recordBridgedError(runtime: "kotlin", fatal: true, type: "Ignored", message: nil, frames: [])

    let reports = storedReports(reporter)
    XCTAssertEqual(reports.count, 1)
    let json = try XCTUnwrap(reports.first)
    XCTAssertEqual(json["kind"] as? String, "crash")
    XCTAssertEqual(json["runtime"] as? String, "react_native")
    XCTAssertEqual(json["screen"] as? String, "cart")
    XCTAssertEqual(json["sessionId"] as? String, "0192b3c4-0000-7000-8000-000000000001")
    XCTAssertEqual((json["breadcrumbs"] as? [[String: Any]])?.count, 2)
    let frames = try XCTUnwrap(json["frames"] as? [[String: Any]])
    XCTAssertEqual(frames.first?["line"] as? Int, 12)
    XCTAssertEqual(frames.first?["col"] as? Int, 4)
    XCTAssertEqual(frames.first?["inApp"] as? Bool, true)
    XCTAssertEqual(frames.last?["module"] as? String, "react-native")
  }

  func testBridgedErrorBeforeStartIsDropped() {
    AppwinCore.setCrashReporterForTesting(nil)
    AppwinCore.recordBridgedError(runtime: "flutter", fatal: false, type: "StateError", message: nil, frames: [])
  }

  func testRecordErrorNamesTheError() {
    let offline = NSError(domain: NSURLErrorDomain, code: -1009)
    XCTAssertEqual(CrashReporter.describe(offline).type, "NSURLErrorDomain(-1009)")
    XCTAssertEqual(CrashReporter.describe(URLError(.notConnectedToInternet)).type, "NSURLErrorDomain(-1009)")
    let swift = CrashReporter.describe(SyncError.offline)
    XCTAssertEqual(swift.type, "AppwinCoreTests.SyncError", "private types lose their unstable context")
    XCTAssertEqual(swift.message, "offline")
    XCTAssertEqual(CrashReporter.describe(SyncError.rejected(email: "a@b.c")).message, "rejected")
    let structError = CrashReporter.describe(ValidationError(field: "secret"))
    XCTAssertEqual(structError.type, "AppwinCoreTests.ValidationError")
    XCTAssertNil(structError.message)
  }

  func testRecordErrorWritesANonFatalWithLiveFrames() async throws {
    let reporter = makeReporter(consent: .unknown)
    reporter.recordError(SyncError.offline, returnAddresses: Thread.callStackReturnAddresses.map(\.uint64Value))
    for _ in 0..<100 where reporter.store.count() == 0 {
      try await Task.sleep(nanoseconds: 10_000_000)
    }
    let json = try XCTUnwrap(storedReports(reporter).first)
    XCTAssertEqual(json["kind"] as? String, "non_fatal")
    let frames = try XCTUnwrap(json["frames"] as? [[String: Any]])
    XCTAssertFalse(frames.isEmpty)
    XCTAssertNotNil(frames.first?["module"] as? String)
    XCTAssertFalse((json["debugImages"] as? [Any] ?? []).isEmpty)
  }

  // MARK: - Uncaught exceptions

  func testExceptionHandlerRecordsThenChainsThePrevious() throws {
    let reporter = makeReporter(consent: .unknown)
    AppwinCore.setCrashReporterForTesting(reporter)
    let original = NSGetUncaughtExceptionHandler()
    NSSetUncaughtExceptionHandler { _ in previousHandlerCalls += 1 }
    defer { NSSetUncaughtExceptionHandler(original) }
    previousHandlerCalls = 0

    ExceptionCrashHandler.install { AppwinCore.crashReporter?.onUncaughtException($0) }
    let installed = try XCTUnwrap(NSGetUncaughtExceptionHandler())
    let exception = NSException(name: .invalidArgumentException, reason: "bad index", userInfo: nil)
    installed(exception)
    installed(exception)

    XCTAssertEqual(previousHandlerCalls, 2)
    let reports = storedReports(reporter)
    XCTAssertEqual(reports.count, 1)
    let json = try XCTUnwrap(reports.first)
    XCTAssertEqual(json["kind"] as? String, "crash")
    XCTAssertEqual((json["exception"] as? [String: Any])?["type"] as? String, "NSInvalidArgumentException")
    XCTAssertEqual((json["exception"] as? [String: Any])?["message"] as? String, "bad index")
  }

  func testReactNativeFatalIsNotReportedTwice() {
    let reporter = makeReporter(consent: .unknown)
    reporter.onUncaughtException(NSException(name: NSExceptionName("RCTFatalException: early"), reason: nil))
    XCTAssertEqual(reporter.store.count(), 1, "without a bridged fatal, the native exception counts")
    reporter.recordBridged(runtime: "react_native", fatal: true, type: "TypeError", message: nil, frames: [])
    reporter.onUncaughtException(
      NSException(name: NSExceptionName("RCTFatalException: Unhandled JS Exception: x"), reason: "x"))
    XCTAssertEqual(reporter.store.count(), 2)
  }

  // MARK: - Breadcrumbs

  func testBreadcrumbsKeepTheLastTwentyNamesAndTheScreen() {
    let crumbs = Breadcrumbs()
    crumbs.screen("home")
    for index in 1...24 { crumbs.event("event_\(index)") }
    let snapshot = crumbs.snapshot()
    XCTAssertEqual(snapshot.entries.count, Breadcrumbs.capacity)
    XCTAssertEqual(snapshot.entries.first?.name, "event_5")
    XCTAssertEqual(snapshot.entries.last?.name, "event_24")
    XCTAssertEqual(snapshot.screen, "home")
    crumbs.clear()
    XCTAssertTrue(crumbs.snapshot().entries.isEmpty)
    XCTAssertNil(crumbs.snapshot().screen)
  }
}

nonisolated(unsafe) private var previousHandlerCalls = 0
