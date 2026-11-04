import XCTest
@testable import AppwinCore

final class SignalCrashTests: XCTestCase {
  private var directory: URL!

  override func setUp() {
    super.setUp()
    directory = FileManager.default.temporaryDirectory
      .appendingPathComponent("appwin-signal-tests-\(UUID().uuidString)")
    try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
  }

  override func tearDown() {
    try? FileManager.default.removeItem(at: directory)
    super.tearDown()
  }

  private let images = [
    BinaryImage(name: "MyApp", addr: 0x1_0000_0000, size: 0x10000, debugId: "aaaa", isMainExecutable: true),
    BinaryImage(name: "StudioKit", addr: 0x1_0010_0000, size: 0x8000, debugId: "bbbb", isMainExecutable: false),
    BinaryImage(name: "libswiftCore.dylib", addr: 0x1_8000_0000, size: 0x100000, debugId: "cccc", isMainExecutable: false),
    BinaryImage(name: "UIKitCore", addr: 0x1_9000_0000, size: 0x100000, debugId: "dddd", isMainExecutable: false),
  ]

  /// Runs the handler's own writer against a real file descriptor, with
  /// memory laid out the way the handler holds it.
  private func writeRecord(signal: Int32, addresses: [UInt64], context: Data) throws -> Data {
    let url = directory.appendingPathComponent("pending")
    let fd = open(url.path, O_WRONLY | O_CREAT | O_TRUNC, 0o600)
    XCTAssertGreaterThanOrEqual(fd, 0)
    let scratch = UnsafeMutablePointer<UInt8>.allocate(capacity: SignalCrashWriter.scratchCapacity)
    defer { scratch.deallocate() }
    addresses.withUnsafeBufferPointer { frames in
      context.withUnsafeBytes { raw in
        SignalCrashWriter.write(
          fd: fd, signal: signal, timeMs: 1_788_500_000_123,
          frames: frames.baseAddress!, count: frames.count,
          context: raw.bindMemory(to: UInt8.self).baseAddress!, contextLength: context.count,
          scratch: scratch)
      }
    }
    close(fd)
    return try Data(contentsOf: url)
  }

  func testPendingFileBecomesAReportWithModulesFromTheSavedImages() throws {
    let context = SignalCrashContext.encode(.init(
      sessionId: "0192b3c4-0000-7000-8000-000000000001",
      screen: "checkout",
      breadcrumbs: [.init(at: Date(timeIntervalSince1970: 1_788_499_999), type: .event, name: "pay_tapped")]))
    let addresses: [UInt64] = [0x1_8000_1234, 0x1_0000_0abc, 0x1_0010_0010, 0x1_9000_0020, 0x42]
    let data = try writeRecord(signal: SIGTRAP, addresses: addresses, context: context)

    let record = try XCTUnwrap(SignalCrashFile.parse(data))
    XCTAssertEqual(record.signal, SIGTRAP)
    XCTAssertEqual(record.timeMs, 1_788_500_000_123)
    XCTAssertEqual(record.addresses, addresses)

    let sidecar = SignalCrashFile.Sidecar(
      context: CrashContext(appVersion: "1.0", appBuild: "7", os: "iOS 17.5", model: "iPhone15,2", sdkVersion: "0.9.2"),
      images: images)
    let report = SignalCrashFile.report(record: record, sidecar: sidecar, inApp: InAppModules(["StudioKit"]))

    XCTAssertEqual(report.kind, .crash)
    XCTAssertEqual(report.exceptionType, "SIGTRAP")
    XCTAssertEqual(report.occurredAt.timeIntervalSince1970, 1_788_500_000.123, accuracy: 0.001)
    XCTAssertEqual(report.context.appVersion, "1.0")
    XCTAssertEqual(report.sessionId, "0192b3c4-0000-7000-8000-000000000001")
    XCTAssertEqual(report.screen, "checkout")
    XCTAssertEqual(report.breadcrumbs.map(\.name), ["pay_tapped"])
    XCTAssertEqual(report.frames.map(\.module), ["libswiftCore.dylib", "MyApp", "StudioKit", "UIKitCore", nil])
    XCTAssertEqual(report.frames.map(\.inApp), [false, true, true, false, false])
    XCTAssertEqual(report.frames.map(\.addr), addresses)
    XCTAssertEqual(Set(report.debugImages.map(\.name)), ["libswiftCore.dylib", "MyApp", "StudioKit", "UIKitCore"])
    XCTAssertNotNil(report.jsonData())
  }

  func testEmptyOrForeignPendingFileIsNoCrash() {
    XCTAssertNil(SignalCrashFile.parse(Data()))
    XCTAssertNil(SignalCrashFile.parse(Data("garbage\n".utf8)))
  }

  func testTornContextStillYieldsTheFrames() throws {
    let data = try writeRecord(signal: SIGSEGV, addresses: [0x1_0000_0010], context: Data("{\"sessi".utf8))
    let record = try XCTUnwrap(SignalCrashFile.parse(data))
    let report = SignalCrashFile.report(
      record: record,
      sidecar: .init(context: CrashContext(appVersion: "1", appBuild: nil, os: "iOS 18.0", model: "x", sdkVersion: "1"), images: images),
      inApp: InAppModules([]))
    XCTAssertEqual(report.exceptionType, "SIGSEGV")
    XCTAssertNil(report.sessionId)
    XCTAssertEqual(report.frames.first?.inApp, true)
  }

  func testContextSnapshotDropsOldestCrumbsToFit() {
    let crumbs = (0..<20).map {
      CrashReport.Breadcrumb(at: Date(), type: .event, name: String(repeating: "e", count: 100) + "\($0)")
    }
    let data = SignalCrashContext.encode(.init(sessionId: nil, screen: nil, breadcrumbs: crumbs), capacity: 1000)
    XCTAssertLessThanOrEqual(data.count, 1000)
    let decoded = SignalCrashContext.decode(data)
    XCTAssertFalse(decoded.breadcrumbs.isEmpty)
    XCTAssertEqual(decoded.breadcrumbs.last?.name, crumbs.last?.name)
  }

  func testFramePointerWalkStaysInsideTheStack() {
    // A fake stack of three frame records: [previous fp, return address].
    let words = UnsafeMutablePointer<UInt64>.allocate(capacity: 16)
    defer { words.deallocate() }
    words.initialize(repeating: 0, count: 16)
    let base = UInt64(UInt(bitPattern: words))
    words[0] = base + 32; words[1] = 0xA1
    words[4] = base + 64; words[5] = 0xA2
    // Points outside the stack: the walk must stop, not read it.
    words[8] = 0xDEAD_0000; words[9] = 0xA3
    let out = UnsafeMutablePointer<UInt64>.allocate(capacity: 16)
    defer { out.deallocate() }

    let count = SignalUnwinder.walk(
      pc: 0x100, lr: 0xA1, fp: base, stackLow: base, stackHigh: base + 128, into: out, capacity: 16)
    XCTAssertEqual(Array(UnsafeBufferPointer(start: out, count: count)), [0x100, 0xA1, 0xA2, 0xA3])

    let capped = SignalUnwinder.walk(
      pc: 0x100, lr: 0, fp: base, stackLow: base, stackHigh: base + 128, into: out, capacity: 2)
    XCTAssertEqual(capped, 2)
  }

  func testLoadedImagesIncludeTheMainExecutableWithAUUID() {
    let loaded = BinaryImages.loaded()
    XCTAssertFalse(loaded.isEmpty)
    XCTAssertEqual(loaded.filter(\.isMainExecutable).count, 1)
    XCTAssertTrue(loaded.allSatisfy { $0.size > 0 && $0.debugId.count == 36 })
  }
}
