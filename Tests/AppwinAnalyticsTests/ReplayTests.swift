import AVFoundation
import UIKit
import XCTest
@_spi(Appwin) import AppwinCore
@testable @_spi(Appwin) import AppwinAnalytics

final class ReplaySamplingTests: XCTestCase {
  func testRateBoundsAndDeterminism() {
    let id = UUID().uuidString.lowercased()
    XCTAssertTrue(ReplaySampling.isSampled(sessionId: id, rate: 1))
    XCTAssertFalse(ReplaySampling.isSampled(sessionId: id, rate: 0))
    XCTAssertEqual(
      ReplaySampling.isSampled(sessionId: id, rate: 0.5),
      ReplaySampling.isSampled(sessionId: id, rate: 0.5))
  }

  func testReadsTheLastEightHexDigits() {
    // 0x7fffffff / 2^32 is just under 0.5.
    XCTAssertTrue(ReplaySampling.isSampled(sessionId: "0198a1b2-0000-7000-8000-00007fffffff", rate: 0.5))
    XCTAssertFalse(ReplaySampling.isSampled(sessionId: "0198a1b2-0000-7000-8000-000080000000", rate: 0.5))
    XCTAssertFalse(ReplaySampling.isSampled(sessionId: "not-a-uuid", rate: 0.5))
  }

  /// UUIDv7 ids of the same minute share their leading digits: sampling
  /// must still split them.
  func testSplitsSessionsOfTheSameInstant() {
    let prefix = "0198a1b2-c3d4-7"
    let sampled = (0..<2000).filter { _ in
      let tail = UUID().uuidString.lowercased().suffix(20)
      return ReplaySampling.isSampled(sessionId: prefix + tail, rate: 0.5)
    }.count
    XCTAssertGreaterThan(sampled, 850)
    XCTAssertLessThan(sampled, 1150)
  }
}

final class ReplayPacerTests: XCTestCase {
  private let start = Date(timeIntervalSince1970: 1_000)

  private func isDue(
    after seconds: TimeInterval, touching: Bool = false, touchedAgo: TimeInterval? = nil,
    scrolling: Bool = false
  ) -> Bool {
    let now = start.addingTimeInterval(seconds)
    return ReplayPacer.isDue(
      now: now, lastFrameAt: start, touching: touching,
      lastTouchAt: touchedAgo.map { now.addingTimeInterval(-$0) }, scrolling: scrolling)
  }

  func testOneFramePerSecondWhenNothingMoves() {
    XCTAssertTrue(ReplayPacer.isDue(
      now: start, lastFrameAt: nil, touching: false, lastTouchAt: nil, scrolling: false))
    XCTAssertFalse(isDue(after: 0.5))
    XCTAssertTrue(isDue(after: 1))
  }

  func testWaitsWhileTouchedOrScrollingThenForTheSettle() {
    XCTAssertFalse(isDue(after: 2, touching: true))
    XCTAssertFalse(isDue(after: 2, scrolling: true))
    XCTAssertFalse(isDue(after: 2, touchedAgo: 0.5))
    XCTAssertTrue(isDue(after: 2, touchedAgo: 1))
  }

  func testNeverWaitsPastTheMaxGap() {
    XCTAssertTrue(isDue(after: ReplayPacer.maxGap, touching: true, scrolling: true))
  }

  func testWaitsWhileTheMainThreadAnimates() {
    let now = start.addingTimeInterval(2)
    XCTAssertFalse(ReplayPacer.isDue(
      now: now, lastFrameAt: start, touching: false, lastTouchAt: nil, scrolling: false, animating: true))
  }

  func testOneWakeUpPerFrameIsAnAnimationAFewPerSecondAreNot() {
    let now: CFTimeInterval = 100
    let frames = (0..<15).map { now - Double($0) / 60 }
    XCTAssertTrue(ReplayMainThreadActivity.isAnimating(frames, now: now))
    let poll = [now - 0.1, now - 0.35, now - 0.6]
    XCTAssertFalse(ReplayMainThreadActivity.isAnimating(poll, now: now))
    // A burst that ended is no longer an animation.
    XCTAssertFalse(ReplayMainThreadActivity.isAnimating(frames.map { $0 - 1 }, now: now))
  }
}

final class ReplayMetaTests: XCTestCase {
  func testEncodesTheContractShape() throws {
    let meta = ReplaySegmentMeta(
      sessionId: "0198a1b2-c3d4-7e5f-8a9b-0c1d2e3f4a5b", seq: 3, runtime: "ios",
      startedAt: "2026-10-05T10:00:00.000Z", endedAt: "2026-10-05T10:00:10.000Z", sentAt: "",
      width: 196, height: 426,
      screens: [.init(t: 0, name: "home")], touches: [.init(t: 1500, x: 0.25, y: 0.5)])
    let sentAt = Date(timeIntervalSince1970: 1_791_201_600)
    let json = try XCTUnwrap(
      JSONSerialization.jsonObject(with: meta.encoded(sentAt: sentAt)) as? [String: Any])
    XCTAssertEqual(
      Set(json.keys),
      ["sessionId", "seq", "kind", "runtime", "startedAt", "endedAt", "sentAt", "width", "height",
       "screens", "touches"])
    XCTAssertEqual(json["kind"] as? String, "video")
    XCTAssertEqual(json["seq"] as? Int, 3)
    XCTAssertEqual(json["sentAt"] as? String, "2026-10-05T12:00:00.000Z")
    let touch = try XCTUnwrap((json["touches"] as? [[String: Any]])?.first)
    XCTAssertEqual(touch["t"] as? Int, 1500)
    XCTAssertEqual(touch["x"] as? Double, 0.25)
    XCTAssertEqual((json["screens"] as? [[String: Any]])?.first?["name"] as? String, "home")
  }
}

final class ReplayQueueTests: XCTestCase {
  private var directory: URL!

  override func setUp() {
    super.setUp()
    directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
  }

  override func tearDown() {
    try? FileManager.default.removeItem(at: directory)
    super.tearDown()
  }

  private func video(bytes: Int) throws -> URL {
    let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".mp4")
    try Data(count: bytes).write(to: url)
    return url
  }

  func testDropsTheOldestPastTheByteCap() throws {
    let queue = ReplayUploadQueue(directory: directory, maxBytes: 1_000_000)
    for seq in 0..<4 {
      XCTAssertTrue(queue.enqueue(meta: .sample(seq: seq), video: try video(bytes: 300_000)))
      Thread.sleep(forTimeInterval: 0.002)
    }
    let pending = queue.pending()
    XCTAssertEqual(pending.count, 3)
    XCTAssertEqual(pending.compactMap { queue.load($0)?.meta.seq }, [1, 2, 3])
    XCTAssertLessThanOrEqual(queue.totalBytes, 1_000_000)
  }

  func testSweepsVideosWithoutMeta() throws {
    let queue = ReplayUploadQueue(directory: directory)
    queue.enqueue(meta: .sample(seq: 0), video: try video(bytes: 10))
    try Data(count: 10).write(to: directory.appendingPathComponent("orphan.mp4"))
    XCTAssertEqual(queue.pending().count, 1)
    XCTAssertFalse(FileManager.default.fileExists(atPath: directory.appendingPathComponent("orphan.mp4").path))
  }
}

final class ReplayUploadTests: XCTestCase {
  func testResponseHandling() {
    XCTAssertEqual(SendOutcome(status: 200, label: "test"), .ok)
    XCTAssertEqual(SendOutcome(status: 400, label: "test"), .fatal)
    XCTAssertEqual(SendOutcome(status: 413, label: "test"), .fatal)
    XCTAssertEqual(SendOutcome(status: 403, label: "test"), .forbidden)
    XCTAssertEqual(SendOutcome(status: 401, label: "test"), .unauthorized)
    XCTAssertEqual(SendOutcome(status: 429, label: "test"), .retryable)
    XCTAssertEqual(SendOutcome(status: 503, label: "test"), .retryable)
    XCTAssertEqual(SendOutcome(status: nil, label: "test"), .retryable)
  }

  private actor StubSender: ReplaySegmentSender {
    var statuses: [Int?]
    private(set) var sent: [Data] = []
    init(_ statuses: [Int?]) { self.statuses = statuses }
    func send(meta: Data, video: Data) async -> Int? {
      sent.append(meta)
      return statuses.isEmpty ? 200 : statuses.removeFirst()
    }
    func sentCount() -> Int { sent.count }
  }

  private final class Flag: @unchecked Sendable {
    var raised = false
  }

  private static func makeQueue(_ count: Int) throws -> ReplayUploadQueue {
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    let queue = ReplayUploadQueue(directory: directory)
    for seq in 0..<count {
      let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
      try Data(count: 8).write(to: url)
      queue.enqueue(meta: .sample(seq: seq), video: url)
      Thread.sleep(forTimeInterval: 0.002)
    }
    return queue
  }

  func testUnauthorizedReauthorizesOnceThenSends() async throws {
    let sender = StubSender([401, 200])
    let uploader = ReplayUploader(
      queue: try Self.makeQueue(1), sender: sender, reauthorize: { true }, canSend: { true },
      onDisabled: {})
    await uploader.flush()
    let sent = await sender.sentCount()
    let pending = await uploader.pendingCount()
    XCTAssertEqual(sent, 2)
    XCTAssertEqual(pending, 0)
  }

  func testForbiddenPurgesAndStops() async throws {
    let sender = StubSender([403])
    let flag = Flag()
    let uploader = ReplayUploader(
      queue: try Self.makeQueue(3), sender: sender, reauthorize: { true }, canSend: { true },
      onDisabled: { flag.raised = true })
    await uploader.flush()
    let sent = await sender.sentCount()
    let pending = await uploader.pendingCount()
    XCTAssertEqual(sent, 1)
    XCTAssertEqual(pending, 0)
    XCTAssertTrue(flag.raised)
  }

  func testTransientFailureKeepsTheQueueAndRefusalDropsOne() async throws {
    let sender = StubSender([413, 503])
    let uploader = ReplayUploader(
      queue: try Self.makeQueue(3), sender: sender, reauthorize: { true }, canSend: { true },
      onDisabled: {}, backoff: .init(base: 60, cap: 60))
    await uploader.flush()
    let pending = await uploader.pendingCount()
    XCTAssertEqual(pending, 2)
  }

  func testNothingLeavesWithoutConsent() async throws {
    let sender = StubSender([])
    let uploader = ReplayUploader(
      queue: try Self.makeQueue(2), sender: sender, reauthorize: { true }, canSend: { false },
      onDisabled: {})
    await uploader.flush()
    let sent = await sender.sentCount()
    XCTAssertEqual(sent, 0)
  }
}

/// Named like the React Native views the masker recognises by class name.
final class RCTParagraphComponentView: UIView {}
final class RCTUITextField: UIView {}
/// Named like WebKit's view: the masker matches it by class name.
final class FakeWKWebView: UIView {}

@MainActor
final class ReplayMaskerTests: XCTestCase {
  private let allMasked = ReplayMaskRules(maskAllText: true, maskAllImages: true)
  private let nothingGlobal = ReplayMaskRules(maskAllText: false, maskAllImages: false)

  private func root() -> UIView {
    UIView(frame: CGRect(x: 0, y: 0, width: 400, height: 800))
  }

  func testInputsAreAlwaysMasked() {
    let root = root()
    let field = UITextField(frame: CGRect(x: 10, y: 10, width: 100, height: 30))
    field.isSecureTextEntry = true
    let editor = UITextView(frame: CGRect(x: 10, y: 50, width: 100, height: 60))
    let rnField = RCTUITextField(frame: CGRect(x: 10, y: 120, width: 100, height: 30))
    [field, editor, rnField].forEach(root.addSubview)
    field.appwinUnmask()
    XCTAssertEqual(
      Set(ReplayMasker.maskRects(in: root, rules: nothingGlobal).map(\.minY)), [10, 50, 120])
  }

  func testTextAndImagesFollowTheRules() {
    let root = root()
    let label = UILabel(frame: CGRect(x: 0, y: 0, width: 50, height: 20))
    let readOnly = UITextView(frame: CGRect(x: 0, y: 30, width: 50, height: 20))
    readOnly.isEditable = false
    let paragraph = RCTParagraphComponentView(frame: CGRect(x: 0, y: 60, width: 50, height: 20))
    let image = UIImageView(frame: CGRect(x: 0, y: 90, width: 50, height: 50))
    [label, readOnly, paragraph, image].forEach(root.addSubview)

    XCTAssertEqual(ReplayMasker.maskRects(in: root, rules: allMasked).count, 4)
    XCTAssertEqual(ReplayMasker.maskRects(in: root, rules: nothingGlobal).count, 0)
    XCTAssertEqual(
      ReplayMasker.maskRects(in: root, rules: .init(maskAllText: false, maskAllImages: true)),
      [CGRect(x: 0, y: 90, width: 50, height: 50)])
  }

  func testUnmaskSparesTextButNotInputsInside() {
    let root = root()
    let container = UIView(frame: CGRect(x: 0, y: 0, width: 200, height: 200))
    container.appwinUnmask()
    container.addSubview(UILabel(frame: CGRect(x: 0, y: 0, width: 50, height: 20)))
    container.addSubview(UITextField(frame: CGRect(x: 0, y: 100, width: 50, height: 20)))
    root.addSubview(container)
    XCTAssertEqual(
      ReplayMasker.maskRects(in: root, rules: allMasked), [CGRect(x: 0, y: 100, width: 50, height: 20)])
  }

  func testExplicitMaskWinsOverTheRules() {
    let root = root()
    let card = UIView(frame: CGRect(x: 20, y: 20, width: 100, height: 100))
    card.addSubview(UILabel(frame: CGRect(x: 0, y: 0, width: 10, height: 10)))
    card.appwinMask()
    root.addSubview(card)
    XCTAssertEqual(
      ReplayMasker.maskRects(in: root, rules: nothingGlobal), [CGRect(x: 20, y: 20, width: 100, height: 100)])
  }

  func testSwiftUIMarkerUnmasksByRegion() {
    let root = root()
    let marker = AppwinMaskMarkerView(frame: CGRect(x: 0, y: 0, width: 100, height: 100))
    marker.appwinUnmask()
    root.addSubview(marker)
    root.addSubview(RCTParagraphComponentView(frame: CGRect(x: 10, y: 10, width: 50, height: 20)))
    root.addSubview(RCTParagraphComponentView(frame: CGRect(x: 10, y: 200, width: 50, height: 20)))
    XCTAssertEqual(
      ReplayMasker.maskRects(in: root, rules: allMasked), [CGRect(x: 10, y: 200, width: 50, height: 20)])
  }

  func testWebViewsAreMaskedWithTextAndImagesShownUnlessUnmasked() {
    let root = root()
    let web = FakeWKWebView(frame: CGRect(x: 0, y: 0, width: 100, height: 100))
    let unmasked = FakeWKWebView(frame: CGRect(x: 0, y: 200, width: 100, height: 100))
    unmasked.appwinUnmask()
    [web, unmasked].forEach(root.addSubview)
    XCTAssertEqual(
      ReplayMasker.maskRects(in: root, rules: nothingGlobal), [CGRect(x: 0, y: 0, width: 100, height: 100)])
  }

  func testHiddenTransparentAndClippedContent() {
    let root = root()
    let hidden = UILabel(frame: CGRect(x: 0, y: 0, width: 50, height: 20))
    hidden.isHidden = true
    let transparent = UILabel(frame: CGRect(x: 0, y: 30, width: 50, height: 20))
    transparent.alpha = 0
    let scroll = UIView(frame: CGRect(x: 0, y: 100, width: 100, height: 100))
    scroll.clipsToBounds = true
    scroll.addSubview(UILabel(frame: CGRect(x: 50, y: 80, width: 100, height: 40)))
    scroll.addSubview(UILabel(frame: CGRect(x: 0, y: 300, width: 100, height: 40)))
    [hidden, transparent, scroll].forEach(root.addSubview)
    XCTAssertEqual(
      ReplayMasker.maskRects(in: root, rules: allMasked), [CGRect(x: 50, y: 180, width: 50, height: 20)])
  }
}

/// Named like the engine's view: the masker matches it by class name.
private final class FakeFlutterView: UIView {}

@MainActor
final class ReplayBridgedMaskTests: XCTestCase {
  private let nothingGlobal = ReplayMaskRules(maskAllText: false, maskAllImages: false)

  override func tearDown() {
    ReplayMasker.bridgedRects = nil
    AppwinAnalytics.setReplayRuntime("ios")
    super.tearDown()
  }

  private func flutterRoot() -> UIView {
    let root = UIView(frame: CGRect(x: 0, y: 0, width: 400, height: 800))
    let flutter = FakeFlutterView(frame: root.bounds)
    flutter.addSubview(UITextField(frame: CGRect(x: 10, y: 10, width: 100, height: 30)))
    root.addSubview(flutter)
    return root
  }

  func testFlutterSurfaceIsMaskedWholeUntilTheFirstReport() {
    AppwinAnalytics.setReplayRuntime("flutter")
    XCTAssertEqual(
      ReplayMasker.maskRects(in: flutterRoot(), rules: nothingGlobal),
      [CGRect(x: 0, y: 0, width: 400, height: 800)])
  }

  func testOnceReportedTheSurfaceIsWalkedLikeAnyView() {
    AppwinAnalytics.setReplayRuntime("flutter")
    AppwinAnalytics.setReplayBridgedMasks([])
    // A platform view inside the surface keeps its native masking.
    XCTAssertEqual(
      ReplayMasker.maskRects(in: flutterRoot(), rules: nothingGlobal),
      [CGRect(x: 10, y: 10, width: 100, height: 30)])
  }

  func testEachReportReplacesThePreviousOne() {
    AppwinAnalytics.setReplayBridgedMasks([CGRect(x: 0, y: 0, width: 10, height: 10)])
    AppwinAnalytics.setReplayBridgedMasks([CGRect(x: 5, y: 5, width: 20, height: 20)])
    XCTAssertEqual(ReplayMasker.bridgedRects, [CGRect(x: 5, y: 5, width: 20, height: 20)])
  }

  func testWithoutTheRuntimeTheSurfaceIsStillMaskedWhole() {
    XCTAssertEqual(
      ReplayMasker.maskRects(in: flutterRoot(), rules: nothingGlobal),
      [CGRect(x: 0, y: 0, width: 400, height: 800)])
  }
}

final class ReplayEncodingTests: XCTestCase {
  func testEncodesBufferedFramesIntoAnH264Mp4() async throws {
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: directory) }
    let buffer = ReplayFrameBuffer(directory: directory.appendingPathComponent("segment"))
    buffer.write(meta: .sample(seq: 0))
    let format = UIGraphicsImageRendererFormat()
    format.scale = 1
    for (index, color) in [UIColor.red, .green, .blue].enumerated() {
      let image = UIGraphicsImageRenderer(size: CGSize(width: 196, height: 426), format: format).image {
        color.setFill()
        $0.fill(CGRect(x: 0, y: 0, width: 196, height: 426))
      }
      buffer.append(image, offsetMs: index * 1000)
    }
    let contents = try XCTUnwrap(buffer.read())
    XCTAssertEqual(contents.frames.map(\.offsetMs), [0, 1000, 2000])
    XCTAssertEqual(contents.meta.endedAt, "2026-10-05T10:00:03.000Z")

    let output = directory.appendingPathComponent("out.mp4")
    try ReplayVideoEncoder.encode(contents.frames, width: 196, height: 426, to: output)
    let tracks = try await AVURLAsset(url: output).loadTracks(withMediaType: .video)
    let track = try XCTUnwrap(tracks.first)
    let size = try await track.load(.naturalSize)
    XCTAssertEqual(size, CGSize(width: 196, height: 426))
    let duration = try await track.load(.timeRange).duration.seconds
    XCTAssertEqual(duration, 3, accuracy: 0.1)
  }
}

extension ReplaySegmentMeta {
  static func sample(seq: Int) -> ReplaySegmentMeta {
    ReplaySegmentMeta(
      sessionId: "0198a1b2-c3d4-7e5f-8a9b-0c1d2e3f4a5b", seq: seq, runtime: "ios",
      startedAt: "2026-10-05T10:00:00.000Z", endedAt: "", sentAt: "", width: 196, height: 426,
      screens: [], touches: [])
  }
}

final class ReplayMaskStyleTests: XCTestCase {
  /// Draws like `ReplayCapture`, then reads the pixels back.
  private func render(_ draw: (CGContext) -> Void) -> CGContext {
    let context = ReplayCapture.bitmapContext(width: 40, height: 20)!
    UIGraphicsPushContext(context)
    draw(context)
    UIGraphicsPopContext()
    return context
  }

  private func pixel(_ context: CGContext, x: Int, y: Int) -> (r: Int, g: Int, b: Int) {
    let bytes = context.data!.assumingMemoryBound(to: UInt8.self)
    let p = y * context.bytesPerRow + x * 4
    return (Int(bytes[p + 2]), Int(bytes[p + 1]), Int(bytes[p]))
  }

  func testBlockTakesTheTintOfWhatItCovers() {
    let orange = { (_: CGContext) in
      UIColor(red: 1, green: 0.5, blue: 0, alpha: 1).setFill()
      UIRectFill(CGRect(x: 0, y: 0, width: 40, height: 20))
    }
    let source = pixel(render(orange), x: 20, y: 10)
    let masked = pixel(render { context in
      orange(context)
      ReplayMaskStyle.paint([CGRect(x: 0, y: 0, width: 40, height: 20)], in: context)
    }, x: 20, y: 10)
    // A light surface: the same tint, a tenth darker.
    XCTAssertEqual(Double(masked.r), Double(source.r) * 0.9, accuracy: 2)
    XCTAssertEqual(Double(masked.g), Double(source.g) * 0.9, accuracy: 2)
    XCTAssertEqual(Double(masked.b), Double(source.b) * 0.9, accuracy: 2)
  }

  func testBlockHidesTheTextUnderIt() {
    let image = render { context in
      UIColor.white.setFill()
      UIRectFill(CGRect(x: 0, y: 0, width: 40, height: 20))
      UIColor.black.setFill()
      UIRectFill(CGRect(x: 10, y: 8, width: 2, height: 4))
      ReplayMaskStyle.paint([CGRect(x: 0, y: 0, width: 40, height: 20)], in: context)
    }
    XCTAssertEqual(pixel(image, x: 11, y: 10).r, pixel(image, x: 30, y: 10).r)
  }
}

/// Named like the engine's hidden text host, which the bridged frame tolerates.
private final class FakeFlutterTextInputView: UIView {}

@MainActor
final class ReplayBridgedFrameTests: XCTestCase {
  /// Top half red, bottom half blue, RGBA as Flutter's `rawRgba` hands it.
  private func halves(width: Int, height: Int) -> Data {
    var bytes = [UInt8]()
    for y in 0..<height {
      for _ in 0..<width { bytes += y < height / 2 ? [255, 0, 0, 255] : [0, 0, 255, 255] }
    }
    return Data(bytes)
  }

  private func rgb(_ image: UIImage, x: Int, y: Int) -> (r: Int, g: Int, b: Int) {
    let context = ReplayCapture.bitmapContext(width: Int(image.size.width), height: Int(image.size.height))!
    UIGraphicsPushContext(context)
    image.draw(at: .zero)
    UIGraphicsPopContext()
    let bytes = context.data!.assumingMemoryBound(to: UInt8.self)
    let p = y * context.bytesPerRow + x * 4
    return (Int(bytes[p + 2]), Int(bytes[p + 1]), Int(bytes[p]))
  }

  func testKeepsTheOrientationAndScalesToTheFrame() throws {
    let image = try XCTUnwrap(ReplayCapture.render(
      rgba: halves(width: 10, height: 20), width: 10, height: 20, masks: [],
      into: 20, 40, pixelsPerPoint: 2))
    XCTAssertEqual(image.size, CGSize(width: 20, height: 40))
    XCTAssertGreaterThan(rgb(image, x: 10, y: 5).r, 200)
    XCTAssertGreaterThan(rgb(image, x: 10, y: 35).b, 200)
  }

  func testPaintsTheMasksSentWithTheFrame() throws {
    // A mask over the top half, in points: two pixels per point.
    let image = try XCTUnwrap(ReplayCapture.render(
      rgba: halves(width: 20, height: 40), width: 20, height: 40,
      masks: [CGRect(x: 0, y: 0, width: 10, height: 10)], into: 20, 40, pixelsPerPoint: 2))
    let masked = rgb(image, x: 10, y: 10)
    // Red is a dark surface: the block lifts it toward white.
    XCTAssertGreaterThan(masked.g, 20)
    XCTAssertGreaterThan(rgb(image, x: 10, y: 35).b, 200)
  }

  private func solid(_ rgba: [UInt8], width: Int, height: Int) -> CGImage {
    let data = Data((0..<(width * height)).flatMap { _ in rgba })
    let provider = CGDataProvider(data: data as CFData)!
    return CGImage(
      width: width, height: height, bitsPerComponent: 8, bitsPerPixel: 32, bytesPerRow: width * 4,
      space: CGColorSpaceCreateDeviceRGB(),
      bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedLast.rawValue),
      provider: provider, decode: nil, shouldInterpolate: false, intent: .defaultIntent)!
  }

  func testAWindowDrawnOverCoversTheMasksOfTheOneUnder() throws {
    // White window masked whole, a black alert window over its bottom half.
    let under = ReplayCapture.Layer(
      image: solid([255, 255, 255, 255], width: 20, height: 40),
      rect: CGRect(x: 0, y: 0, width: 20, height: 40), masks: [CGRect(x: 0, y: 0, width: 20, height: 40)])
    let over = ReplayCapture.Layer(
      image: solid([0, 0, 0, 255], width: 20, height: 20),
      rect: CGRect(x: 0, y: 20, width: 20, height: 20), masks: [])
    let image = try XCTUnwrap(ReplayCapture.compose([under, over], width: 20, height: 40, pixelsPerPoint: 1))
    // The masked white is a tenth darker; the window over it is untouched.
    XCTAssertEqual(Double(rgb(image, x: 10, y: 10).r), 229.5, accuracy: 3)
    XCTAssertEqual(rgb(image, x: 10, y: 30).r, 0)
  }

  private func window(with surface: UIView) -> UIWindow {
    let window = UIWindow(frame: CGRect(x: 0, y: 0, width: 100, height: 200))
    window.isHidden = false
    surface.frame = window.bounds
    window.addSubview(surface)
    return window
  }

  func testAFullScreenSurfaceAloneIsUsed() {
    let surface = UIView()
    let key = window(with: surface)
    XCTAssertTrue(ReplayCapture.showsOnly(surface, key: key, windows: [key]))
    surface.addSubview(FakeFlutterTextInputView(frame: CGRect(x: 0, y: 0, width: 1, height: 1)))
    XCTAssertTrue(ReplayCapture.showsOnly(surface, key: key, windows: [key]))
  }

  func testAnythingNativeOnScreenFallsBackToTheNativeCapture() {
    let surface = UIView()
    let key = window(with: surface)
    // A platform view inside the surface.
    let platformView = UIView(frame: CGRect(x: 0, y: 0, width: 50, height: 50))
    surface.addSubview(platformView)
    XCTAssertFalse(ReplayCapture.showsOnly(surface, key: key, windows: [key]))
    platformView.removeFromSuperview()
    // A native screen presented over it.
    key.addSubview(UIView(frame: key.bounds))
    XCTAssertFalse(ReplayCapture.showsOnly(surface, key: key, windows: [key]))
  }

  func testAnotherWindowOrAPartialSurfaceFallsBack() {
    let surface = UIView()
    let key = window(with: surface)
    let alert = UIWindow(frame: key.bounds)
    alert.isHidden = false
    XCTAssertFalse(ReplayCapture.showsOnly(surface, key: key, windows: [key, alert]))
    surface.frame = CGRect(x: 0, y: 0, width: 100, height: 100)
    XCTAssertFalse(ReplayCapture.showsOnly(surface, key: key, windows: [key]))
  }
}
