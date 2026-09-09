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
  /// Single manager of the SKAN/AdAttributionKit conversion value
  /// (ADR-0038) - lives with analytics: no product adoption, no updates.
  let conversionValues: ConversionValueManager
  private let monitor = NWPathMonitor()
  /// Written only on the monitor queue.
  private var wasSatisfied = true

  init(pipeline: EventPipeline, conversionValues: ConversionValueManager) {
    self.pipeline = pipeline
    self.conversionValues = conversionValues

    monitor.pathUpdateHandler = { [pipeline] path in
      let satisfied = path.status == .satisfied
      // Only the offline -> online edge triggers: the callback also fires
      // for interface changes that do not end a wait.
      if satisfied && !self.wasSatisfied {
        Task { await pipeline.networkRegained() }
      }
      self.wasSatisfied = satisfied
    }
    monitor.start(queue: DispatchQueue(label: "appwin.analytics.network"))

    #if canImport(UIKit)
    // didBecomeActive rather than willEnterForeground: only the former fires
    // on a cold launch, and a repeated one is a no-op inside the session.
    NotificationCenter.default.addObserver(
      forName: UIApplication.didBecomeActiveNotification, object: nil, queue: .main
    ) { [pipeline] _ in
      Task { await pipeline.onForeground() }
    }
    NotificationCenter.default.addObserver(
      forName: UIApplication.didEnterBackgroundNotification, object: nil, queue: .main
    ) { [pipeline] _ in
      // A background task buys the flush its network time; without it the
      // suspension can land mid-request.
      let taskId = MainActor.assumeIsolated {
        UIApplication.shared.beginBackgroundTask(expirationHandler: nil)
      }
      Task {
        await pipeline.onBackground()
        await MainActor.run { UIApplication.shared.endBackgroundTask(taskId) }
      }
    }
    #endif
  }
}

private let analyticsRuntimeHolder = OSAllocatedUnfairLock<AnalyticsRuntime?>(initialState: nil)

/// Consent set before `configure` (a consent-screen studio starting in
/// `unknown`). Applied synchronously when the pipeline is built, so nothing
/// can slip out in between.
private let pendingConsentHolder = OSAllocatedUnfairLock<AnalyticsConsent?>(initialState: nil)

extension AppwinCore {
  // MARK: - Analytics (Core v2 event pipeline, ADR-0036 §3)

  /// Wired by `AppwinAnalytics.initialize()` once availability said yes -
  /// never by `configure`: capture must not exist in an app that did not
  /// adopt the product. Everything heavier than object creation runs in the
  /// pipeline's first turn, off the main thread. Idempotent.
  package static func startAnalytics() {
    guard let apiClient = client, let projectAppId else { return }
    let alreadyWired = analyticsRuntimeHolder.withLock { $0 != nil }
    guard !alreadyWired else { return }
    let appVersion = deviceInfo?.appVersion

    let config = AnalyticsConfig()
    let prefs = UserDefaultsAnalyticsPrefs()
    let keyPrefix = "appwin.analytics.\(projectAppId)."
    let directory = FileManager.default
      .urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
      .appendingPathComponent("appwin/analytics/\(projectAppId)", isDirectory: true)
    let pipeline = EventPipeline(
      store: EventStore(
        directory: directory, maxBatch: config.maxBatch, maxQueueEvents: config.maxQueueEvents),
      sessions: SessionManager(
        prefs: prefs, keyPrefix: keyPrefix, appVersion: appVersion,
        timeout: config.sessionTimeout, maxAge: config.maxSessionAge),
      consentStore: ConsentStore(
        prefs: prefs, keyPrefix: keyPrefix,
        initial: pendingConsentHolder.withLock { $0 }),
      sender: ApiEventSender(client: { apiClient }),
      config: config,
      prefs: prefs,
      keyPrefix: keyPrefix,
      reauthorize: { (try? await AppwinCore.bootstrapSession()) != nil })

    let conversionValues = ConversionValueManager(
      prefs: prefs, keyPrefix: keyPrefix, client: { apiClient })
    analyticsRuntimeHolder.withLock {
      $0 = AnalyticsRuntime(pipeline: pipeline, conversionValues: conversionValues)
    }
    // The product just came alive: open the session (and emit `app_install`
    // on a first run) without waiting for a first `track`.
    Task { await pipeline.onForeground() }
    // Install registered at value 0 on first run, then schema refresh.
    Task { await conversionValues.start() }
    // Advertising identity (ADR-0038): IDFA under advertising consent +
    // ATT, on its own channel - never in the event stream.
    startAdIdentity(prefs: prefs, keyPrefix: keyPrefix, client: { apiClient })
  }

  private nonisolated static var analyticsPipeline: EventPipeline? {
    analyticsRuntimeHolder.withLock { $0?.pipeline }
  }

  // MARK: - Product entry points (AppwinAnalytics is the public surface)

  // `package` on purpose: the pipeline lives in Core (ADR-0036 §3) but the
  // public API belongs to the AppwinAnalytics product, like every other
  // product façade. Only targets of this package can reach these.

  package nonisolated static func track(_ name: String, props: [String: AnalyticsValue]? = nil) {
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
    // Conversion value ride-along (ADR-0038): a schema event raises the
    // SKAN/AdAttributionKit value, independently of the ingest pipeline.
    if let conversionValues = analyticsRuntimeHolder.withLock({ $0?.conversionValues }) {
      Task { await conversionValues.onEvent(name) }
    }
    adSignals?.onEvent(name: name, eventId: eventId, props: props)
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
  }

  package nonisolated static func flush() {
    guard let pipeline = analyticsPipeline else { return }
    Task { await pipeline.flushNow() }
  }

  package nonisolated static func setConsent(_ consent: AnalyticsConsent) {
    guard let pipeline = analyticsPipeline else {
      // Legal, not a misuse: a consent-screen studio sets `.unknown` BEFORE
      // `configure` so the very first events cannot leave under the
      // opt-out default.
      pendingConsentHolder.withLock { $0 = consent }
      return
    }
    Task { await pipeline.setConsent(consent) }
  }

  /// Loud in debug, silent in release: an integration mistake must surface
  /// during development and never crash a shipped app.
  private nonisolated static func reportAnalyticsMisuse(_ detail: String) {
    #if DEBUG
    print("[Appwin] analytics: \(detail)")
    #endif
  }
}
