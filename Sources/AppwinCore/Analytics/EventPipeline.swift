import Foundation

/// Tuning knobs of the pipeline. One instance, shared names with the Kotlin
/// mirror - a change here must land there too.
struct AnalyticsConfig: Sendable {
  var flushAt = 20
  var flushInterval: TimeInterval = 30
  var maxBatch = 500
  var maxQueueEvents = 10_000
  var sessionTimeout: TimeInterval = 30 * 60
  var maxSessionAge: TimeInterval = 24 * 60 * 60
  var backoffBase: TimeInterval = 2
  var backoffCap: TimeInterval = 300
  var quotaCooldown: TimeInterval = 60 * 60
}

/// The analytics pipeline: one actor serializes everything - enqueue, flush,
/// consent, session transitions - so none of the parts it owns needs locks.
///
/// Contract (ADR-0036 §3): persisted queue, batched sends, multi-trigger
/// flush, exponential backoff with jitter, at-least-once with server-side
/// dedup by eventId, queue-before-consent. Public entry points never throw
/// and never block the caller: they hop into the actor.
actor EventPipeline {
  private let store: EventStore
  private let sessions: SessionManager
  private let consentStore: ConsentStore
  private let sender: any EventSender
  private let config: AnalyticsConfig
  private let backoff: Backoff
  private let prefs: AnalyticsPrefs
  private let keyPrefix: String
  /// Re-bootstraps the SDK session after a 401. Returns false when the
  /// bearer could not be refreshed.
  private let reauthorize: @Sendable () async -> Bool
  private let now: @Sendable () -> Date

  private var started = false
  private var flushing = false
  private var pendingFlush = false
  private var attempt = 0
  private var quotaCooldownUntil: Date?
  private var retryTask: Task<Void, Never>?
  private var timerTask: Task<Void, Never>?

  init(
    store: EventStore,
    sessions: SessionManager,
    consentStore: ConsentStore,
    sender: any EventSender,
    config: AnalyticsConfig,
    prefs: AnalyticsPrefs,
    keyPrefix: String,
    reauthorize: @escaping @Sendable () async -> Bool,
    now: @escaping @Sendable () -> Date = Date.init
  ) {
    self.store = store
    self.sessions = sessions
    self.consentStore = consentStore
    self.sender = sender
    self.config = config
    self.backoff = Backoff(base: config.backoffBase, cap: config.backoffCap)
    self.prefs = prefs
    self.keyPrefix = keyPrefix
    self.reauthorize = reauthorize
    self.now = now
  }

  /// First turn of the actor: all the I/O `configure()` must not pay for.
  func start() {
    guard !started else { return }
    started = true
    store.start()
    // A queue left over from a run before the consent turned denied must
    // not survive it.
    if consentStore.consent == .denied { store.purgeAll() }
  }

  // MARK: - Enqueue

  func enqueue(name: String, screen: String?, props: [String: AnalyticsValue]?, occurredAt: Date) {
    guard consentStore.consent != .denied else { return }
    start()
    appendSessionEvents()
    if let line = WireEvent.line(
      name: name, occurredAt: occurredAt, sessionId: sessions.sessionId,
      screen: screen, props: props
    ) {
      recordDrops(store.append(line))
    }
    if consentStore.consent == .granted, store.queuedEventCount >= config.flushAt {
      flushTrigger()
    }
  }

  // MARK: - Consent

  func setConsent(_ consent: AnalyticsConsent) {
    guard consent != consentStore.consent else { return }
    consentStore.set(consent)
    switch consent {
    case .denied:
      start()
      store.purgeAll()
      sessions.reset()
      retryTask?.cancel()
      retryTask = nil
      attempt = 0
    case .granted:
      start()
      flushTrigger()
    case .unknown:
      break
    }
  }

  // MARK: - Triggers

  /// All flush triggers funnel here and coalesce: one flush in flight
  /// absorbs the triggers that arrive during it.
  func flushTrigger() {
    guard consentStore.consent == .granted else { return }
    if let until = quotaCooldownUntil, now() < until { return }
    if flushing {
      pendingFlush = true
      return
    }
    flushing = true
    Task { await self.performFlush() }
  }

  /// Network came back: the wait is over, retry immediately.
  func networkRegained() {
    attempt = 0
    retryTask?.cancel()
    retryTask = nil
    flushTrigger()
  }

  func flushNow() {
    start()
    store.rotateCurrent()
    flushTrigger()
  }

  func onForeground() {
    start()
    appendSessionEvents()
    startTimer()
    flushTrigger()
  }

  func onBackground() {
    start()
    sessions.onBackground()
    timerTask?.cancel()
    timerTask = nil
    store.rotateCurrent()
    flushTrigger()
  }

  // MARK: - Flush loop

  private func performFlush() async {
    defer {
      flushing = false
      if pendingFlush {
        pendingFlush = false
        flushTrigger()
      }
    }
    start()
    store.rotateCurrent()
    var reauthorized = false
    while let batch = store.nextReadyBatch() {
      guard consentStore.consent == .granted else { return }
      switch await sender.send(lines: batch.lines) {
      case .ok:
        store.delete(file: batch.file)
        attempt = 0
      case .quotaExceeded:
        // The server dropped the data by design; resending would be noise.
        // The queue keeps accepting (the plan can change), overflow prunes.
        store.delete(file: batch.file)
        quotaCooldownUntil = now().addingTimeInterval(config.quotaCooldown)
        return
      case .fatal:
        recordDrops(batch.lines.count)
        store.delete(file: batch.file)
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
      await self.flushTrigger()
    }
  }

  private func startTimer() {
    timerTask?.cancel()
    timerTask = Task {
      while !Task.isCancelled {
        try? await Task.sleep(nanoseconds: UInt64(config.flushInterval * 1_000_000_000))
        guard !Task.isCancelled else { return }
        await self.timerTick()
      }
    }
  }

  private func timerTick() {
    if store.queuedEventCount > 0 {
      store.rotateCurrent()
      flushTrigger()
    }
  }

  // MARK: - Internals

  /// Test seam: the store is actor-confined, tests must read it from inside.
  func queuedEventCount() -> Int { store.queuedEventCount }

  private func appendSessionEvents() {
    for event in sessions.touch() {
      let props: [String: AnalyticsValue]? = event.durationMs.map { ["duration_ms": .int(Int($0))] }
      if let line = WireEvent.line(
        name: event.name, occurredAt: event.occurredAt, sessionId: event.sessionId,
        screen: nil, props: props
      ) {
        recordDrops(store.append(line))
      }
    }
  }

  /// Overflow drops are invisible by nature; the persisted counter is the
  /// trace, and the future diagnostics surface will read it.
  private func recordDrops(_ count: Int) {
    guard count > 0 else { return }
    let key = keyPrefix + "droppedCount"
    let total = (prefs.string(forKey: key).flatMap(Int.init) ?? 0) + count
    prefs.set(String(total), forKey: key)
  }
}
