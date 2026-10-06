import Foundation
import UIKit
@_spi(Appwin) import AppwinCore

/// Session replay (ADR-0057): one masked frame per second of the foreground
/// scene, cut into ten-second H.264 segments attached to the analytics
/// session, then queued for upload.
///
/// Records only while the app is active, consent is `granted`, and the
/// session is sampled and under its hour. Frames of the open segment live on
/// disk until it is encoded, so a crash loses nothing but the encoding.
@MainActor
final class ReplayRecorder {
  private(set) static var shared: ReplayRecorder?

  /// Set by the Flutter and React Native bridges before `initialize`.
  static var runtime = "ios"

  private struct OpenSegment {
    var meta: ReplaySegmentMeta
    let startedAt: Date
    var frames = 0
  }

  private let io = DispatchQueue(label: "appwin.replay.io", qos: .utility)
  private let buffer: ReplayFrameBuffer
  private let uploader: ReplayUploader
  private let scratch: URL
  private let stateKey: String

  private var config = AppwinReplayConfig()
  private var state: ReplaySessionState?
  private var segment: OpenSegment?
  private var lastScreen: String?
  private var timer: Timer?
  private var active = false
  private var disabled = false
  /// Set once a `denied` consent has wiped what was recorded, so the wipe
  /// runs once per denial rather than every tick.
  private var purgedForDenial = false
  private var observers: [NSObjectProtocol] = []
  private let touches = ReplayTouchRecognizer()

  private init(projectAppId: String) {
    let caches = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0]
      .appendingPathComponent("appwin/replay/\(projectAppId)", isDirectory: true)
    let support = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
      .appendingPathComponent("appwin/replay/\(projectAppId)", isDirectory: true)
    buffer = ReplayFrameBuffer(directory: caches.appendingPathComponent("segment", isDirectory: true))
    scratch = caches.appendingPathComponent("encoding", isDirectory: true)
    stateKey = "appwin.replay.\(projectAppId).session"
    uploader = ReplayUploader(
      queue: ReplayUploadQueue(directory: support.appendingPathComponent("queue", isDirectory: true)),
      onDisabled: { await ReplayRecorder.shared?.disable(purge: true) })
  }

  /// Starts recording when the server and the consent allow it. Idempotent.
  static func start() {
    guard shared == nil, let projectAppId = AppwinCore.projectAppId else { return }
    let recorder = ReplayRecorder(projectAppId: projectAppId)
    shared = recorder
    Task { await recorder.boot() }
  }

  private func boot() async {
    let availability = await AppwinCore.replayAvailability()
    guard let config = availability.config else {
      // A definite no: whatever an earlier run recorded will never be accepted.
      if case .unavailable = availability.result { Self.discardStoredData() }
      Self.shared = nil
      return
    }
    self.config = config
    if AppwinCore.analyticsConsent == .denied {
      purgeForDenial()
    } else {
      recoverLeftover()
    }
    touches.onTap = { [weak self] point in self?.onTap(point) }
    let center = NotificationCenter.default
    observers = [
      center.addObserver(forName: UIApplication.didBecomeActiveNotification, object: nil, queue: .main) { _ in
        MainActor.assumeIsolated { ReplayRecorder.shared?.resume() }
      },
      center.addObserver(forName: UIApplication.willResignActiveNotification, object: nil, queue: .main) { _ in
        MainActor.assumeIsolated { ReplayRecorder.shared?.pause() }
      },
    ]
    if UIApplication.shared.applicationState == .active { resume() }
  }

  /// The rules a bridge applies to what it draws itself, `nil` once off.
  var bridgeConfig: AppwinReplayConfig? { disabled ? nil : config }

  private func resume() {
    guard !disabled, !active else { return }
    active = true
    Task { await uploader.flush(resetBackoff: true) }
    guard AppwinCore.analyticsConsent == .granted else { return startTimer() }
    Task {
      // Opens (or rotates) the analytics session before the first frame, so
      // a relaunch never records under the previous, expired one.
      let sessionId = await AppwinCore.activeAnalyticsSessionId()
      guard active, !disabled else { return }
      if let sessionId { adopt(sessionId) }
      startTimer()
    }
  }

  private func pause() {
    active = false
    timer?.invalidate()
    timer = nil
    touches.view?.removeGestureRecognizer(touches)
    closeSegment()
  }

  /// Off for the rest of the process: replay refused by the server (403), or
  /// no encoder on this device. A denied consent is not a reason: it purges
  /// and recording resumes once consent is granted again.
  func disable(purge: Bool) {
    disabled = true
    ReplayMasker.bridgedRects = nil
    // Dropped rather than encoded: nothing recorded before a purge may be
    // queued after it.
    if purge { segment = nil }
    pause()
    observers.forEach(NotificationCenter.default.removeObserver)
    observers = []
    if purge { purgeStorage() }
  }

  /// Dropped rather than encoded: nothing recorded before a purge may be
  /// queued after it.
  private func purgeForDenial() {
    guard !purgedForDenial else { return }
    purgedForDenial = true
    segment = nil
    touches.view?.removeGestureRecognizer(touches)
    purgeStorage()
  }

  private func purgeStorage() {
    io.async { [buffer] in buffer.clear() }
    Task { await uploader.purge() }
  }

  private func startTimer() {
    timer?.invalidate()
    let timer = Timer(timeInterval: ReplayLimits.frameInterval, repeats: true) { _ in
      MainActor.assumeIsolated { ReplayRecorder.shared?.tick() }
    }
    // Common modes: a scroll in progress must not stop the capture.
    RunLoop.main.add(timer, forMode: .common)
    self.timer = timer
  }

  private func tick() {
    let consent = AppwinCore.analyticsConsent
    if consent != .denied { purgedForDenial = false }
    switch consent {
    case .denied: return purgeForDenial()
    case .unknown: return closeSegment()
    case .granted: break
    }
    guard let sessionId = AppwinCore.analyticsSessionId else { return closeSegment() }
    if sessionId != state?.sessionId {
      closeSegment()
      adopt(sessionId)
    }
    guard var state, ReplaySampling.isSampled(sessionId: sessionId, rate: config.sampleRate),
          !state.budgetExhausted
    else { return closeSegment() }

    attachTouches()
    let rules = ReplayMaskRules(maskAllText: config.maskAllText, maskAllImages: config.maskAllImages)
    guard let frame = ReplayCapture.frame(rules: rules) else { return }
    if let open = segment, open.meta.width != frame.width || open.meta.height != frame.height {
      closeSegment()
    }
    let now = Date()
    if segment == nil {
      segment = OpenSegment(
        meta: ReplaySegmentMeta(
          sessionId: sessionId, seq: state.nextSeq, runtime: Self.runtime,
          startedAt: ReplaySegmentMeta.timestamp(now), endedAt: "", sentAt: "",
          width: frame.width, height: frame.height,
          screens: lastScreen.map { [.init(t: 0, name: $0)] } ?? [], touches: []),
        startedAt: now)
      state.nextSeq += 1
    }
    guard var open = segment else { return }
    let offset = offsetMs(now, in: open)
    open.frames += 1
    segment = open
    state.recordedSeconds += 1
    state.save(key: stateKey)
    self.state = state

    let meta = open.meta
    io.async { [buffer] in
      buffer.append(frame.image, offsetMs: offset)
      buffer.write(meta: meta)
    }
    if open.frames >= ReplayLimits.segmentFrames { closeSegment() }
  }

  private func adopt(_ sessionId: String) {
    if state?.sessionId == sessionId { return }
    if let saved = ReplaySessionState.load(key: stateKey), saved.sessionId == sessionId {
      state = saved
    } else {
      state = ReplaySessionState(sessionId: sessionId)
      state?.save(key: stateKey)
    }
  }

  /// The window the taps are read from follows the key window.
  private func attachTouches() {
    guard let window = ReplayCapture.keyWindow(), touches.view !== window else { return }
    touches.view?.removeGestureRecognizer(touches)
    window.addGestureRecognizer(touches)
  }

  private func onTap(_ point: CGPoint) {
    guard var open = segment, open.meta.touches.count < ReplayLimits.maxTouches else { return }
    open.meta.touches.append(.init(t: offsetMs(Date(), in: open), x: point.x, y: point.y))
    segment = open
  }

  /// From the facade's `screen(_:)`, the same names the pipeline records.
  func onScreen(_ name: String, at date: Date) {
    let name = String(name.prefix(128))
    guard !name.isEmpty else { return }
    lastScreen = name
    guard var open = segment, open.meta.screens.count < ReplayLimits.maxScreens else { return }
    open.meta.screens.append(.init(t: offsetMs(date, in: open), name: name))
    segment = open
  }

  private func offsetMs(_ date: Date, in segment: OpenSegment) -> Int {
    min(max(Int(date.timeIntervalSince(segment.startedAt) * 1000), 0), ReplayLimits.maxOffsetMs)
  }

  private func closeSegment() {
    guard let open = segment else { return }
    segment = nil
    let meta = open.meta
    // The last touches and screens arrived after the last frame was written.
    io.async { [buffer] in buffer.write(meta: meta) }
    encodeBuffer()
  }

  /// A segment left on disk by a process that died mid-recording.
  private func recoverLeftover() {
    encodeBuffer()
  }

  private func encodeBuffer() {
    let application = UIApplication.shared
    // The app may be leaving the foreground: the encoding needs its seconds.
    // Out of time, the task is ended early: an expired task left open gets
    // the app killed. The encoding then runs only as long as suspension lets it.
    let task = BackgroundTask(application: application)
    io.async { [buffer, scratch, uploader] in
      defer { task.end() }
      guard let contents = buffer.read() else { return buffer.clear() }
      buffer.clear()
      try? FileManager.default.createDirectory(at: scratch, withIntermediateDirectories: true)
      let output = scratch.appendingPathComponent("\(UUID().uuidString).mp4")
      do {
        try ReplayVideoEncoder.encode(
          contents.frames, width: contents.meta.width, height: contents.meta.height, to: output)
      } catch ReplayVideoEncoder.Failure.unavailable(let reason) {
        NSLog("[Appwin] replay: the video encoder could not start (%@), recording is off", reason)
        Task { @MainActor in ReplayRecorder.shared?.disable(purge: false) }
        return
      } catch {
        NSLog("[Appwin] replay: segment dropped, encoding failed (%@)", "\(error)")
        try? FileManager.default.removeItem(at: output)
        return
      }
      let size = (try? output.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0
      guard size > 0, size <= ReplayLimits.segmentMaxBytes else {
        try? FileManager.default.removeItem(at: output)
        return
      }
      let meta = contents.meta
      Task {
        await uploader.enqueue(meta: meta, video: output)
        await uploader.flush()
      }
    }
  }

  /// When `sessionReplay: false` or replay is off: nothing recorded earlier
  /// may leave the device later.
  static func discardStoredData() {
    guard let projectAppId = AppwinCore.projectAppId else { return }
    let fileManager = FileManager.default
    for base in [FileManager.SearchPathDirectory.cachesDirectory, .applicationSupportDirectory] {
      let url = fileManager.urls(for: base, in: .userDomainMask)[0]
        .appendingPathComponent("appwin/replay/\(projectAppId)", isDirectory: true)
      try? fileManager.removeItem(at: url)
    }
  }
}

/// A background task ended once, either by the work or by its expiration.
@MainActor
private final class BackgroundTask: Sendable {
  private var identifier: UIBackgroundTaskIdentifier = .invalid
  private let application: UIApplication

  init(application: UIApplication) {
    self.application = application
    identifier = application.beginBackgroundTask { [weak self] in
      MainActor.assumeIsolated { self?.endNow() }
    }
  }

  nonisolated func end() {
    Task { @MainActor in self.endNow() }
  }

  private func endNow() {
    guard identifier != .invalid else { return }
    application.endBackgroundTask(identifier)
    identifier = .invalid
  }
}
