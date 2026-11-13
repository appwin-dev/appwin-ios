import Foundation

protocol CrashSender: Sendable {
  func send(reports: [String]) async -> SendOutcome
}

/// POSTs stored reports to `/api/sdk/v1/crashes` (ADR-0056), frozen URL.
struct ApiCrashSender: CrashSender {
  /// Resolved per send: the client does not exist before `configure()`.
  let client: @Sendable () -> ClientApi?

  private static let iso8601 = Date.ISO8601FormatStyle(includingFractionalSeconds: true)

  func send(reports: [String]) async -> SendOutcome {
    guard let client = client() else { return .retryable }
    // Stored reports are already wire JSON: joined, never re-parsed.
    let sentAt = Date().formatted(Self.iso8601)
    let body = Data("{\"crashes\":[\(reports.joined(separator: ","))],\"sentAt\":\"\(sentAt)\"}".utf8)
    do {
      let (status, data) = try await client.postRaw(path: "/api/sdk/v1/crashes", body: body)
      return SendOutcome(status: status, data: data, label: "crash batch")
    } catch {
      return .retryable
    }
  }
}

/// Uploads the stored reports: one flush at a time, exponential backoff on
/// transient failures, one session re-bootstrap per flush on a 401.
actor CrashUploader {
  static let batchSize = 20

  private let store: CrashStore
  private let sender: any CrashSender
  private let reauthorize: @Sendable () async -> Bool
  private let canSend: @Sendable () -> Bool
  private let backoff: Backoff

  private var flushing = false
  private var pendingFlush = false
  private var attempt = 0
  private var retryTask: Task<Void, Never>?

  init(
    store: CrashStore,
    sender: any CrashSender,
    reauthorize: @escaping @Sendable () async -> Bool,
    canSend: @escaping @Sendable () -> Bool,
    backoff: Backoff = .ingest
  ) {
    self.store = store
    self.sender = sender
    self.reauthorize = reauthorize
    self.canSend = canSend
    self.backoff = backoff
  }

  /// `resetBackoff`: the network came back or the app returned to the
  /// foreground, the wait is over.
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

  func cancelRetry() {
    retryTask?.cancel()
    retryTask = nil
    attempt = 0
  }

  private func performFlush() async {
    var reauthorized = false
    while canSend() {
      let batch = store.pending(limit: Self.batchSize)
      if batch.isEmpty { return }
      switch await sender.send(reports: batch.map(\.json)) {
      case .ok, .quotaExceeded, .fatal, .forbidden:
        // A deterministic refusal retried would block every report queued
        // behind it.
        batch.forEach { store.delete($0.url) }
        attempt = 0
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
