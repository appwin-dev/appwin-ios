import Foundation
import Network
import os
#if canImport(UIKit)
import UIKit
#endif

/// Everything the pipeline needs that outlives a call: the actor itself, the
/// network monitor and the lifecycle observers. One instance per process,
/// parked in a lock so the `nonisolated` public API can reach it from any
/// thread.
private final class AnalyticsRuntime: @unchecked Sendable {
  let pipeline: EventPipeline
  private let monitor = NWPathMonitor()
  /// Written only on the monitor queue.
  private var wasSatisfied = true
  /// Held for the process: releasing it would unsubscribe from `AppLifecycle`.
  @MainActor private var lifecycleToken: AnyObject?

  /// Test-only: ends the monitor and, by releasing the runtime, the
  /// `AppLifecycle` subscription.
  func stop() { monitor.cancel() }

  init(pipeline: EventPipeline) {
    self.pipeline = pipeline

    monitor.pathUpdateHandler = { [pipeline] path in
      let satisfied = path.status == .satisfied
      // Only the offline -> online edge triggers: the callback also fires
      // for interface changes that do not end a wait.
      if satisfied && !self.wasSatisfied {
        Task { await pipeline.networkRegained() }
        AppwinCore.crashReporter?.flush(resetBackoff: true)
      }
      self.wasSatisfied = satisfied
    }
    monitor.start(queue: DispatchQueue(label: "appwin.analytics.network"))

    #if canImport(UIKit)
    // A repeated foreground is a no-op inside the session.
    Task { @MainActor in
      lifecycleToken = AppLifecycle.subscribe(
        onForeground: { [pipeline] in
          Task { await pipeline.onForeground() }
          AppwinCore.crashReporter?.flush(resetBackoff: true)
        },
        onBackground: { [pipeline] in
          // A background task buys the flush its network time; without it the
          // suspension can land mid-request.
          let taskId = UIApplication.shared.beginBackgroundTask(expirationHandler: nil)
          Task {
            await pipeline.onBackground()
            await MainActor.run { UIApplication.shared.endBackgroundTask(taskId) }
          }
        })
    }
    #endif
  }
}

private let analyticsRuntimeHolder = OSAllocatedUnfairLock<AnalyticsRuntime?>(initialState: nil)

/// Consent set before `configure` (a consent-screen studio starting in
/// `unknown`). Applied synchronously when the pipeline is built, so nothing
/// can slip out in between.
private let pendingConsentHolder =
  OSAllocatedUnfairLock<[(ConsentState, ConsentPurpose?)]>(initialState: [])

private let eventBusInstance = EventBus(isGranted: { AppwinCore.consentState(for: $0) == .granted })

extension AppwinCore {
  // MARK: - Analytics (Core v2 event pipeline, ADR-0036 §3)

  /// Starts the pipeline if it is not running. `configure` already does it
  /// (ADR-0061), so this only matters to a product calling it ahead of
  /// `configure` having run. Idempotent.
  package static func startAnalytics() {
    ensureEventPipeline()
  }

  /// Core's shared event pipeline (ADR-0036 §3): the queue that persists,
  /// batches and ingests events into ClickHouse. It belongs to neither
  /// Analytics nor Attribution - both products call this, whichever
  /// `initialize()` runs first, and the pipeline is built exactly once.
  /// Idempotent. Everything heavier than object creation runs off the main
  /// thread on the pipeline's first turn.
  package static func ensureEventPipeline() {
    guard let apiClient = client, let projectAppId else { return }
    let alreadyWired = analyticsRuntimeHolder.withLock { $0 != nil }
    guard !alreadyWired else { return }
    let appVersion = deviceInfo?.appVersion

    let config = AnalyticsConfig()
    let prefs = UserDefaultsAnalyticsPrefs()
    let keyPrefix = analyticsKeyPrefix(projectAppId)
    let directory = FileManager.default
      .urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
      .appendingPathComponent("appwin/analytics/\(projectAppId)", isDirectory: true)
    applyPendingConsent(prefs: prefs, keyPrefix: keyPrefix)
    installIsFresh = SessionManager.isFreshInstall(
      prefs: prefs, keyPrefix: keyPrefix, deviceKnownBeforeConfigure: deviceKnownBeforeConfigure)
    let pipeline = EventPipeline(
      store: EventStore(
        directory: directory, maxBatch: config.maxBatch, maxQueueEvents: config.maxQueueEvents),
      sessions: SessionManager(
        prefs: prefs, keyPrefix: keyPrefix, appVersion: appVersion,
        timeout: config.sessionTimeout, maxAge: config.maxSessionAge,
        deviceKnownBeforeConfigure: deviceKnownBeforeConfigure),
      consentStore: ConsentStore(prefs: prefs, keyPrefix: keyPrefix),
      sender: ApiEventSender(client: { apiClient }),
      config: config,
      prefs: prefs,
      keyPrefix: keyPrefix,
      reauthorize: { (try? await AppwinCore.bootstrapSession()) != nil })

    analyticsRuntimeHolder.withLock {
      $0 = AnalyticsRuntime(pipeline: pipeline)
    }
    // The pipeline just came alive: open the session (and emit `app_install`
    // on a first run) without waiting for a first `track`. Not when the app
    // was woken in the background (silent push, background fetch): nobody
    // opened it, and `AppLifecycle` delivers the launch when someone does.
    if !launchedInBackground() {
      Task { await pipeline.onForeground() }
    }
  }

  /// Whether the app was launched into the background (a silent push, a
  /// background fetch): read once, when the pipeline is built. A test seam.
  static var launchedInBackground: () -> Bool = {
    #if canImport(UIKit)
    UIApplication.shared.applicationState == .background
    #else
    false
    #endif
  }

  /// Test-only: forgets the running pipeline so the next `configure` builds a new one.
  static func resetEventPipelineForTesting() {
    analyticsRuntimeHolder.withLock { runtime in
      runtime?.stop()
      runtime = nil
    }
  }

  nonisolated static func analyticsKeyPrefix(_ projectAppId: String) -> String {
    "appwin.analytics.\(projectAppId)."
  }

  /// Core's internal bus (ADR-0061): subscribers are the installed products.
  nonisolated static var eventBus: EventBus { eventBusInstance }

  /// The consent of one purpose, as persisted: the store is the single
  /// source, written synchronously by `setConsent`. Before `configure`, what
  /// was staged for it. Readable from any thread.
  @_spi(Appwin) public nonisolated static func consentState(for purpose: ConsentPurpose) -> ConsentState {
    guard let projectAppId else {
      return pendingConsentHolder.withLock { pending in
        pending.last { $0.1 == nil || $0.1 == purpose }?.0 ?? .granted
      }
    }
    let prefs = UserDefaultsAnalyticsPrefs()
    let keyPrefix = analyticsKeyPrefix(projectAppId)
    applyPendingConsent(prefs: prefs, keyPrefix: keyPrefix)
    return ConsentStore.stored(prefs: prefs, keyPrefix: keyPrefix, purpose: purpose)
  }

  /// Writes the consents staged before `configure`, in call order, then
  /// forgets them. Under the holder's lock: a `setConsent` racing with the
  /// first reads cannot be overwritten by an older staged one.
  nonisolated static func applyPendingConsent(prefs: AnalyticsPrefs, keyPrefix: String) {
    pendingConsentHolder.withLock { pending in
      for (state, purpose) in pending {
        ConsentStore.write(prefs: prefs, keyPrefix: keyPrefix, state, for: purpose)
      }
      pending = []
    }
  }

  @available(*, deprecated, message: "Use consentState(for: .analytics)")
  @_spi(Appwin) public nonisolated static var analyticsConsent: ConsentState {
    consentState(for: .analytics)
  }

  /// Test-only: the staged consents are process-wide, and a configured
  /// process keeps its answers in the standard defaults.
  nonisolated static func resetConsentForTesting() {
    pendingConsentHolder.withLock { $0 = [] }
    if let projectAppId {
      for purpose in ConsentPurpose.allCases {
        UserDefaults.standard.removeObject(
          forKey: analyticsKeyPrefix(projectAppId) + "consent." + purpose.rawValue)
      }
    }
  }

  /// Stages a consent set before `configure`.
  nonisolated static func stageConsentForTesting(_ state: ConsentState, for purpose: ConsentPurpose?) {
    pendingConsentHolder.withLock { $0.append((state, purpose)) }
  }

  /// Current analytics session id as persisted, without touching the session.
  /// Cheap enough to poll: a change is the rotation signal.
  @_spi(Appwin) public nonisolated static var analyticsSessionId: String? {
    guard let projectAppId else { return nil }
    return SessionManager.storedId(prefs: UserDefaultsAnalyticsPrefs(), keyPrefix: analyticsKeyPrefix(projectAppId))
  }

  nonisolated static var analyticsPipeline: EventPipeline? {
    analyticsRuntimeHolder.withLock { $0?.pipeline }
  }

  // MARK: - Product entry points (AppwinAnalytics is the public surface)

  // `track` and `setConsent` are Core's public surface (ADR-0061); `screen`
  // and `flush` stay `package`, reached through AppwinAnalytics.

  /// Records an event of your app (a purchase, a finished onboarding...).
  /// Every product installed in the app picks it up from this one call.
  ///
  /// `name` must match `^[a-z][a-z0-9_]{0,63}$` and not shadow a reserved
  /// name (`session_start`, `session_end`, `screen_view`, `app_install`,
  /// `app_update`, `app_open`, `app_background`, `push_opt_in`, `push_opened`); invalid events, and calls before `configure`, are dropped
  /// with a debug log. Props are capped at 20 keys; string values are
  /// truncated to 256 characters.
  public nonisolated static func track(_ name: String, props: [String: AnalyticsValue]? = nil) {
    guard let pipeline = analyticsPipeline else {
      return reportAnalyticsMisuse("AppwinCore.configure(projectAppId:) has not been called")
    }
    guard AnalyticsValidation.isValidEventName(name),
          !AnalyticsValidation.reservedNames.contains(name) else {
      return reportAnalyticsMisuse(
        "invalid event name '\(name)' (expected ^[a-z][a-z0-9_]{0,63}$, not reserved)")
    }
    let props = AnalyticsValidation.sanitizeProps(props)
    let occurredAt = Date()
    // Generated here, not at enqueue time: the ad-signals adapters must
    // carry the SAME id as our ingest (cross-source dedup, ADR-0038).
    let eventId = UUID().uuidString.lowercased()
    Task {
      await pipeline.enqueue(
        name: name, screen: nil, props: props, occurredAt: occurredAt, eventId: eventId)
    }
    eventBus.publish(EventBus.Event(name: name, eventId: eventId, props: props))
  }

  /// An event the SDK emits itself (`push_opened`, `push_opt_in`): `track`
  /// without the reserved-name check, which exists to keep the studio's own
  /// events from shadowing these. Dropped before `configure`, like `track`.
  package nonisolated static func emitAutomaticEvent(
    _ name: String, props: [String: AnalyticsValue]? = nil
  ) {
    guard let pipeline = analyticsPipeline else {
      return reportAnalyticsMisuse("AppwinCore.configure(projectAppId:) has not been called")
    }
    let props = AnalyticsValidation.sanitizeProps(props)
    let occurredAt = Date()
    let eventId = UUID().uuidString.lowercased()
    Task {
      await pipeline.enqueueAutomatic(
        name: name, props: props, occurredAt: occurredAt, eventId: eventId)
    }
    eventBus.publish(EventBus.Event(name: name, eventId: eventId, props: props))
  }

  package nonisolated static func screen(_ name: String) {
    guard let pipeline = analyticsPipeline else {
      return reportAnalyticsMisuse("AppwinCore.configure(projectAppId:) has not been called")
    }
    let screen = String(name.prefix(AnalyticsValidation.maxScreenLength))
    let occurredAt = Date()
    Task {
      await pipeline.enqueue(name: "screen_view", screen: screen, props: nil, occurredAt: occurredAt)
    }
    crashReporter?.onScreen(screen)
  }

  package nonisolated static func flush() {
    guard let pipeline = analyticsPipeline else { return }
    Task { await pipeline.flushNow() }
    crashReporter?.flush()
  }

  /// Sets the consent state of a purpose (`analytics`, `marketing`,
  /// `advertising`), or of the three when `purpose` is omitted. The default
  /// is `.granted` (opt-out). Call `setConsent(.unknown)` at launch (before
  /// `configure` works too) if your app has a consent screen: events are then
  /// kept on the device and never sent until you relay the answer. `.denied`
  /// on the three purges the queue and mutes capture; on some of them, events
  /// leave carrying only the purposes still granted.
  ///
  /// `AppwinAttribution.setAdvertisingConsent` stays the only switch of the
  /// advertising identifier (IDFA) and of the ad networks.
  public nonisolated static func setConsent(_ consent: ConsentState, for purpose: ConsentPurpose? = nil) {
    guard let projectAppId else {
      // Legal, not a misuse: a consent-screen studio sets `.unknown` BEFORE
      // `configure` so the very first events cannot leave under the
      // opt-out default. Staged, written when `configure` runs.
      pendingConsentHolder.withLock { $0.append((consent, purpose)) }
      return
    }
    // Persisted here, synchronously and in call order: the bus and the
    // pipeline both read this store, so none can end up on another answer.
    let prefs = UserDefaultsAnalyticsPrefs()
    let keyPrefix = analyticsKeyPrefix(projectAppId)
    pendingConsentHolder.withLock { pending in
      for (state, staged) in pending {
        ConsentStore.write(prefs: prefs, keyPrefix: keyPrefix, state, for: staged)
      }
      pending = []
      ConsentStore.write(prefs: prefs, keyPrefix: keyPrefix, consent, for: purpose)
    }
    if let pipeline = analyticsPipeline {
      // A signal, not a value: the pipeline re-reads the store when it runs.
      Task { await pipeline.consentChanged() }
    }
    if purpose == nil || purpose == .analytics {
      crashReporter?.onConsentChanged(consentState(for: .analytics))
    }
  }

  /// Loud in debug, silent in release: an integration mistake must surface
  /// during development and never crash a shipped app.
  nonisolated static func reportAnalyticsMisuse(_ detail: String) {
    #if DEBUG
    print("[Appwin] analytics: \(detail)")
    #endif
  }
}
