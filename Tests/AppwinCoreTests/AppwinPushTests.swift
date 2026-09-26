import XCTest
@testable import AppwinCore

@MainActor
final class AppwinPushTests: XCTestCase {

  override func setUp() {
    super.setUp()
    AppwinPush.reset()
  }

  // MARK: - Parsing

  func testParsesTheCurrentContract() throws {
    let payload = try XCTUnwrap(AppwinPushPayload([
      "aps": ["alert": ["title": "Anna", "body": "Hello"]],
      "appwinType": "support.message",
      "appwinVersion": "1",
      "deeplink": "appwin://support/conversation/c1",
      "imageUrl": "https://cdn.example/i.png",
    ]))
    XCTAssertEqual(payload.type, "support.message")
    XCTAssertEqual(payload.product, "support")
    XCTAssertEqual(payload.deeplink, "appwin://support/conversation/c1")
    XCTAssertEqual(payload.imageUrl, "https://cdn.example/i.png")
    XCTAssertEqual(payload.title, "Anna")
    XCTAssertEqual(payload.body, "Hello")
    XCTAssertEqual(payload.raw["appwinVersion"], "1")
  }

  func testRenderedContentOverridesTheAlert() throws {
    let payload = try XCTUnwrap(AppwinPushPayload(
      ["appwinType": "support.message", "aps": ["alert": "raw body"]],
      title: "Localized",
      body: "Rendered"
    ))
    XCTAssertEqual(payload.title, "Localized")
    XCTAssertEqual(payload.body, "Rendered")
  }

  func testProductIsTheTypePrefix() {
    XCTAssertEqual(AppwinPushPayload(["appwinType": "notifications.campaign"])?.product, "notifications")
    XCTAssertEqual(AppwinPushPayload(["appwinType": "community.reply"])?.product, "community")
  }

  func testInAppPendingBelongsToNotifications() {
    XCTAssertEqual(AppwinPushPayload(["appwinType": "inapp.pending"])?.product, "notifications")
  }

  func testLegacyDeeplinkWithoutTypeUsesTheDeeplinkHost() {
    let payload = AppwinPushPayload(["deeplink": "appwin://support/conversation/c1"])
    XCTAssertEqual(payload?.product, "support")
    XCTAssertNil(payload?.type)
  }

  func testLegacyTripleSlashDeeplink() {
    XCTAssertEqual(AppwinPushPayload(["deeplink": "appwin:///support/conversation/c1"])?.product, "support")
  }

  func testLegacyDeliveryIdWithoutTypeIsNotifications() {
    let payload = AppwinPushPayload(["deliveryId": "d1", "deeplink": "https://example.com"])
    XCTAssertEqual(payload?.product, "notifications")
    XCTAssertEqual(payload?.deliveryId, "d1")
  }

  func testReadsKeysNestedUnderData() {
    let payload = AppwinPushPayload(["data": ["deliveryId": "d1", "appwinType": "notifications.campaign"]])
    XCTAssertEqual(payload?.product, "notifications")
    XCTAssertEqual(payload?.deliveryId, "d1")
  }

  func testForeignPushIsNotAppwin() {
    XCTAssertFalse(AppwinPush.isAppwinPush(["aps": ["alert": "hi"], "deeplink": "https://example.com"]))
    XCTAssertFalse(AppwinPush.isAppwinPush(["gcm.message_id": "1"]))
    XCTAssertTrue(AppwinPush.isAppwinPush(["appwinType": "support.message"]))
  }

  func testRouteSplitsProductAndPath() throws {
    let route = try XCTUnwrap(AppwinPushPayload.route(of: URL(string: "appwin://Support/conversation/a%20b")!))
    XCTAssertEqual(route.product, "support")
    XCTAssertEqual(route.path, ["conversation", "a b"])
    XCTAssertNil(AppwinPushPayload.route(of: URL(string: "https://support/conversation/1")!))
  }

  // MARK: - Routing

  func testTapGoesToTheRegisteredProduct() async {
    let support = RecordingHandler()
    AppwinPush.register(.support, handler: support)

    XCTAssertTrue(AppwinPush.handleTap(["appwinType": "support.message", "deeplink": "appwin://support/conversation/c1"]))
    await support.waitForTaps(1)

    XCTAssertEqual(support.taps.first?.deeplink, "appwin://support/conversation/c1")
  }

  func testTapBeforeRegistrationIsReplayedOnRegister() async {
    XCTAssertTrue(AppwinPush.handleTap(["appwinType": "support.message", "deeplink": "appwin://support/conversation/c1"]))
    XCTAssertNotNil(AppwinPush.pendingTap(for: "support"))

    let support = RecordingHandler()
    AppwinPush.register(.support, handler: support)
    await support.waitForTaps(1)

    XCTAssertEqual(support.taps.map(\.deeplink), ["appwin://support/conversation/c1"])
    XCTAssertNil(AppwinPush.pendingTap(for: "support"))
  }

  func testOnlyTheLatestQueuedTapIsReplayed() async {
    AppwinPush.handleTap(["deeplink": "appwin://support/conversation/old"])
    AppwinPush.handleTap(["deeplink": "appwin://support/conversation/new"])

    let support = RecordingHandler()
    AppwinPush.register(.support, handler: support)
    await support.waitForTaps(1)

    XCTAssertEqual(support.taps.map(\.deeplink), ["appwin://support/conversation/new"])
  }

  func testForeignTapIsNotConsumed() {
    XCTAssertFalse(AppwinPush.handleTap(["aps": ["alert": "hi"]]))
  }

  func testForegroundAndMessageDefaultToNotConsumed() async {
    XCTAssertFalse(AppwinPush.handleForeground(["appwinType": "support.message"]))
    let consumed = await AppwinPush.handleMessage(["appwinType": "inapp.pending"])
    XCTAssertFalse(consumed)

    let notifications = RecordingHandler(consumes: true)
    AppwinPush.register(.notifications, handler: notifications)
    let consumedNow = await AppwinPush.handleMessage(["appwinType": "inapp.pending"])
    XCTAssertTrue(consumedNow)
    XCTAssertTrue(AppwinPush.handleForeground(["appwinType": "notifications.campaign"]))
  }

  func testUnregisteredProductQueuesAgain() {
    AppwinPush.register(.support, handler: RecordingHandler())
    AppwinPush.unregister(.support)
    AppwinPush.handleTap(["deeplink": "appwin://support/conversation/c1"])
    XCTAssertNotNil(AppwinPush.pendingTap(for: "support"))
  }

  func testInternalDeeplinkIsDispatchedNotOpened() async {
    let support = RecordingHandler()
    AppwinPush.register(.support, handler: support)

    AppwinPush.openDeeplink(URL(string: "appwin://support/conversation/c9")!, from: .notifications)
    await support.waitForTaps(1)

    XCTAssertEqual(support.taps.first?.product, "support")
  }

  func testDeeplinkBackToItsSourceIsDropped() {
    AppwinPush.openDeeplink(URL(string: "appwin://notifications/x")!, from: .notifications)
    XCTAssertNil(AppwinPush.pendingTap(for: "notifications"))
  }
}

@MainActor
private final class RecordingHandler: AppwinPushHandler {
  private(set) var taps: [AppwinPushPayload] = []
  private let consumes: Bool

  init(consumes: Bool = false) {
    self.consumes = consumes
  }

  func onTap(_ payload: AppwinPushPayload) async {
    taps.append(payload)
  }

  func onForeground(_ payload: AppwinPushPayload) -> Bool { consumes }

  func onMessage(_ payload: AppwinPushPayload) async -> Bool { consumes }

  /// Taps are dispatched on a `Task`, so they land a hop later.
  func waitForTaps(_ count: Int) async {
    for _ in 0 ..< 100 where taps.count < count {
      await Task.yield()
    }
  }
}
