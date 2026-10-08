import Foundation
@_spi(Appwin) import AppwinCore

protocol ReplaySegmentSender: Sendable {
  /// The HTTP status, nil without a response.
  func send(meta: Data, video: Data) async -> Int?
}

struct ApiReplaySegmentSender: ReplaySegmentSender {
  func send(meta: Data, video: Data) async -> Int? {
    await AppwinCore.postSdkMultipart(
      path: "/api/sdk/v1/replays/segments",
      parts: [
        AppwinMultipartPart(name: "meta", data: meta),
        AppwinMultipartPart(name: "segment", filename: "segment.mp4", contentType: "video/mp4", data: video),
      ])?.status
  }
}

/// Sends the queue oldest first: one flush at a time, exponential backoff on
/// transient failures, one session re-bootstrap per flush on a 401.
actor ReplayUploader {
  private let queue: ReplayUploadQueue
  private let sender: any ReplaySegmentSender
  private let reauthorize: @Sendable () async -> Bool
  private let canSend: @Sendable () -> Bool
  private let onDisabled: @Sendable () async -> Void
  private let backoff: Backoff
  private let now: @Sendable () -> Date

  private var flushing = false
  private var pendingFlush = false
  private var attempt = 0
  private var retryTask: Task<Void, Never>?

  init(
    queue: ReplayUploadQueue,
    sender: any ReplaySegmentSender = ApiReplaySegmentSender(),
    reauthorize: @escaping @Sendable () async -> Bool = { await AppwinCore.reauthorizeSdkSession() },
    canSend: @escaping @Sendable () -> Bool = { AppwinCore.analyticsConsent == .granted },
    onDisabled: @escaping @Sendable () async -> Void,
    backoff: Backoff = .ingest,
    now: @escaping @Sendable () -> Date = Date.init
  ) {
    self.queue = queue
    self.sender = sender
    self.reauthorize = reauthorize
    self.canSend = canSend
    self.onDisabled = onDisabled
    self.backoff = backoff
    self.now = now
  }

  func enqueue(meta: ReplaySegmentMeta, video: URL) {
    queue.enqueue(meta: meta, video: video)
  }

  func purge() {
    retryTask?.cancel()
    retryTask = nil
    queue.purgeAll()
  }

  /// `resetBackoff`: the app came back to the foreground, the wait is over.
  func flush(resetBackoff: Bool = false) async {
    if resetBackoff {
      attempt = 0
      retryTask?.cancel()
      retryTask = nil
    }
    if flushing {
      pendingFlush = true
      return
    }
    flushing = true
    await performFlush()
    flushing = false
    if pendingFlush {
      pendingFlush = false
      await flush()
    }
  }

  /// Test seam.
  func pendingCount() -> Int { queue.pending().count }

  private func performFlush() async {
    var reauthorized = false
    var entries = queue.pending()[...]
    while canSend(), let entry = entries.first {
      guard let (meta, video) = queue.load(entry), let body = try? meta.encoded(sentAt: now()) else {
        queue.delete(entry)
        entries.removeFirst()
        continue
      }
      switch SendOutcome(status: await sender.send(meta: body, video: video), label: "replay segment") {
      case .ok, .quotaExceeded, .fatal:
        // A deterministic refusal (400, 413) retried would block every
        // segment queued behind it.
        queue.delete(entry)
        entries.removeFirst()
        attempt = 0
      case .forbidden:
        // Replay is switched off for this project.
        queue.purgeAll()
        await onDisabled()
        return
      case .unauthorized:
        if !reauthorized, await reauthorize() {
          reauthorized = true
          continue
        }
        scheduleRetry()
        return
      case .retryable:
        scheduleRetry()
        return
      }
    }
  }

  private func scheduleRetry() {
    let delay = backoff.delay(attempt: attempt)
    attempt += 1
    retryTask?.cancel()
    retryTask = Task {
      try? await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))
      guard !Task.isCancelled else { return }
      await self.flush()
    }
  }
}
