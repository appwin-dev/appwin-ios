import XCTest
@testable import AppwinCore

final class EventStoreTests: XCTestCase {
  private var directory: URL!

  override func setUp() {
    super.setUp()
    directory = FileManager.default.temporaryDirectory
      .appendingPathComponent("appwin-store-tests-\(UUID().uuidString)")
  }

  override func tearDown() {
    try? FileManager.default.removeItem(at: directory)
    super.tearDown()
  }

  private func makeStore(maxBatch: Int = 500, maxQueueEvents: Int = 10_000) -> EventStore {
    let store = EventStore(directory: directory, maxBatch: maxBatch, maxQueueEvents: maxQueueEvents)
    store.start()
    return store
  }

  private func eventLine(_ i: Int) -> String { "{\"eventId\":\"e\(i)\"}" }

  func testAppendRotatesAtMaxBatch() {
    let store = makeStore(maxBatch: 3)
    store.append(eventLine(1))
    store.append(eventLine(2))
    XCTAssertNil(store.nextReadyBatch())
    store.append(eventLine(3))
    let batch = store.nextReadyBatch()
    XCTAssertEqual(batch?.lines, [eventLine(1), eventLine(2), eventLine(3)])
    XCTAssertEqual(store.queuedEventCount, 3)
  }

  func testOverflowDropsOldestReadyFileAndReportsCount() {
    let store = makeStore(maxBatch: 2, maxQueueEvents: 4)
    var dropped = 0
    for i in 1...5 { dropped += store.append(eventLine(i)) }
    XCTAssertEqual(dropped, 2)
    XCTAssertEqual(store.queuedEventCount, 3)
    XCTAssertEqual(store.nextReadyBatch()?.lines, [eventLine(3), eventLine(4)])
  }

  func testCorruptLineIsDroppedAlone() throws {
    let store = makeStore()
    let content = "\(eventLine(1))\n{\"eventId\":\"tru\n\(eventLine(3))\n"
    try content.write(
      to: directory.appendingPathComponent("ready-\(Uuid7.generate()).jsonl"),
      atomically: true, encoding: .utf8)
    store.start()
    XCTAssertEqual(store.nextReadyBatch()?.lines, [eventLine(1), eventLine(3)])
  }

  func testUnreadableFileIsDeleted() throws {
    let store = makeStore()
    // A directory with a batch name: any read attempt fails.
    try FileManager.default.createDirectory(
      at: directory.appendingPathComponent("ready-\(Uuid7.generate()).jsonl"),
      withIntermediateDirectories: true)
    store.start()
    XCTAssertNil(store.nextReadyBatch())
    let leftovers = try FileManager.default.contentsOfDirectory(atPath: directory.path)
    XCTAssertTrue(leftovers.isEmpty, "\(leftovers)")
  }

  func testReadyBatchesComeBackInChronologicalOrder() {
    let store = makeStore()
    store.append(eventLine(1))
    store.rotateCurrent()
    store.append(eventLine(2))
    store.rotateCurrent()
    let first = store.nextReadyBatch()
    XCTAssertEqual(first?.lines, [eventLine(1)])
    store.delete(file: first!.file)
    XCTAssertEqual(store.nextReadyBatch()?.lines, [eventLine(2)])
  }

  func testStartRebuildsCountersAfterRelaunch() {
    let store = makeStore(maxBatch: 2)
    for i in 1...3 { store.append(eventLine(i)) }
    let relaunched = EventStore(directory: directory, maxBatch: 2, maxQueueEvents: 10_000)
    relaunched.start()
    XCTAssertEqual(relaunched.queuedEventCount, 3)
    XCTAssertEqual(relaunched.nextReadyBatch()?.lines, [eventLine(1), eventLine(2)])
  }

  func testPurgeAllEmptiesTheQueue() {
    let store = makeStore(maxBatch: 2)
    for i in 1...3 { store.append(eventLine(i)) }
    store.purgeAll()
    XCTAssertEqual(store.queuedEventCount, 0)
    XCTAssertNil(store.nextReadyBatch())
  }
}
