import XCTest

@testable import AppwinCore

final class ConversionValuesTests: XCTestCase {
  private final class UpdateRecorder: @unchecked Sendable {
    private let lock = NSLock()
    private var calls: [(Int, String)] = []
    func record(_ fine: Int, _ coarse: String) {
      lock.lock()
      defer { lock.unlock() }
      calls.append((fine, coarse))
    }
    var all: [(Int, String)] {
      lock.lock()
      defer { lock.unlock() }
      return calls
    }
  }

  private func makeManager(
    prefs: InMemoryAnalyticsPrefs = InMemoryAnalyticsPrefs()
  ) -> (ConversionValueManager, UpdateRecorder, InMemoryAnalyticsPrefs) {
    let recorder = UpdateRecorder()
    let manager = ConversionValueManager(
      prefs: prefs, keyPrefix: "t.", client: { nil },
      applyUpdate: { fine, coarse in recorder.record(fine, coarse) })
    return (manager, recorder, prefs)
  }

  func testFirstStartRegistersInstallAtZero() async {
    let (manager, recorder, _) = makeManager()
    await manager.start()
    await manager.start()
    XCTAssertEqual(recorder.all.map(\.0), [0], "install registered exactly once")
    XCTAssertEqual(recorder.all.first?.1, "low")
  }

  func testSchemaEventRaisesValueOnce() async {
    let (manager, recorder, _) = makeManager()
    await manager.onEvent("start_trial")
    await manager.onEvent("start_trial")
    XCTAssertEqual(recorder.all.map(\.0), [32])
    XCTAssertEqual(recorder.all.first?.1, "medium")
  }

  func testValueNeverGoesDown() async {
    let (manager, recorder, _) = makeManager()
    await manager.onEvent("purchase")
    await manager.onEvent("start_trial")
    XCTAssertEqual(recorder.all.map(\.0), [63], "trial after purchase must not lower the value")
  }

  func testUnknownEventIsIgnored() async {
    let (manager, recorder, _) = makeManager()
    await manager.onEvent("screen_view")
    XCTAssertTrue(recorder.all.isEmpty)
  }

  func testCachedSchemaSurvivesRestart() async throws {
    let prefs = InMemoryAnalyticsPrefs()
    let cached = ConversionSchema(
      version: 4, rules: [ConversionRule(event: "level_up", value: 10, coarse: "low")])
    let json = String(data: try JSONEncoder().encode(cached), encoding: .utf8)
    prefs.set(json, forKey: "t.cv.schema")

    let (manager, recorder, _) = makeManager(prefs: prefs)
    let schema = await manager.currentSchema()
    XCTAssertEqual(schema, cached)
    await manager.onEvent("level_up")
    XCTAssertEqual(recorder.all.map(\.0), [10])
  }

  func testCurrentValuePersistsAcrossManagers() async {
    let prefs = InMemoryAnalyticsPrefs()
    let (managerA, recorderA, _) = makeManager(prefs: prefs)
    await managerA.onEvent("purchase")
    XCTAssertEqual(recorderA.all.map(\.0), [63])

    let (managerB, recorderB, _) = makeManager(prefs: prefs)
    await managerB.onEvent("start_trial")
    XCTAssertTrue(recorderB.all.isEmpty, "persisted 63 blocks a lower update after restart")
  }
}
