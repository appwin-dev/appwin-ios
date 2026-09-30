import Foundation
import os
#if os(iOS) && canImport(AppTrackingTransparency)
import AppTrackingTransparency
#endif

private let adIdentityHolder = OSAllocatedUnfairLock<AdIdentityReporter?>(initialState: nil)
private let adSignalsHolder = OSAllocatedUnfairLock<AdSignalsHub?>(initialState: nil)
/// SKAN/AdAttributionKit conversion value manager (ADR-0038). Lives with
/// Attribution: `track` reads it to raise the value, and it stays nil for an
/// app that only adopted Analytics.
private let conversionValuesHolder = OSAllocatedUnfairLock<ConversionValueManager?>(initialState: nil)

/// Same buffering story as the analytics consent, advertising side: a
/// consent-screen studio may answer before the runtime exists.
private let pendingAdvertisingConsentHolder =
  OSAllocatedUnfairLock<AdvertisingConsent?>(initialState: nil)

/// Ad-signals debug mode (test events): read by the hub at activation,
/// so it must be set before `AppwinAttribution.initialize()` - the
/// network SDKs cannot re-init once started.
private let adSignalsDebugHolder = OSAllocatedUnfairLock<Bool>(initialState: false)

extension AppwinCore {
  // MARK: - Attribution (ADR-0038, S2S activation)

  /// Wired by `AppwinAttribution.initialize()` once availability said yes.
  /// A product in its own right: it starts Core's shared event pipeline
  /// (so its conversion signals ride the same ingest as Analytics) and then
  /// its own acquisition machinery - SKAN conversion values, advertising
  /// identity (IDFA) and the optional ad-network adapters (TikTok).
  /// Idempotent.
  package static func startAttribution() {
    guard let apiClient = client, let projectAppId else { return }
    // The only thing Attribution shares with Analytics: Core's pipeline.
    ensureEventPipeline()
    let alreadyWired = adIdentityHolder.withLock { $0 != nil }
    guard !alreadyWired else { return }

    let prefs = UserDefaultsAnalyticsPrefs()
    let keyPrefix = "appwin.analytics.\(projectAppId)."

    let conversionValues = ConversionValueManager(
      prefs: prefs, keyPrefix: keyPrefix, client: { apiClient })
    conversionValuesHolder.withLock { $0 = conversionValues }
    // Install registered at value 0 on first run, then schema refresh.
    Task { await conversionValues.start() }
    // Advertising identity (ADR-0038): IDFA under advertising consent +
    // ATT, on its own channel - never in the event stream.
    startAdIdentity(prefs: prefs, keyPrefix: keyPrefix, client: { apiClient })
  }

  /// The conversion value manager, once `startAttribution` has run. `track`
  /// reads it to raise the SKAN value on schema events.
  nonisolated static var conversionValues: ConversionValueManager? {
    conversionValuesHolder.withLock { $0 }
  }

  /// Wired from `startAttribution`: the identity report needs the bearer
  /// machinery a product start brings, and `configure` stays 100% local.
  static func startAdIdentity(
    prefs: AnalyticsPrefs,
    keyPrefix: String,
    client: @escaping @Sendable () -> ClientApi?
  ) {
    let alreadyWired = adIdentityHolder.withLock { $0 != nil }
    guard !alreadyWired else { return }
    let reporter = AdIdentityReporter(
      prefs: prefs,
      keyPrefix: keyPrefix,
      client: client,
      reauthorize: { (try? await AppwinCore.bootstrapSession()) != nil })
    adIdentityHolder.withLock { $0 = reporter }
    let pending = pendingAdvertisingConsentHolder.withLock { value in
      defer { value = nil }
      return value
    }
    // Ad-signals adapters (ADR-0038): optional network modules the app
    // may ship (TikTok App Events). Consent + dashboard wiring decide
    // whether they run; track() fans out through the hub.
    let hub = AdSignalsHub(
      client: client,
      consent: { AdIdentityReporter.storedConsent(prefs: prefs, keyPrefix: keyPrefix) },
      debugMode: { adSignalsDebugHolder.withLock { $0 } })
    adSignalsHolder.withLock { $0 = hub }
    Task {
      if let pending { await reporter.setConsent(pending) }
      await reporter.start()
      await hub.start()
    }
  }

  nonisolated static var adSignals: AdSignalsHub? {
    adSignalsHolder.withLock { $0 }
  }

  /// Advertising destination consent (ADR-0038): the opt-in switch for
  /// activating signals towards ad networks and collecting the device
  /// advertising identifier. The public surface is
  /// `AppwinAttribution.setAdvertisingConsent`; the switch lives in Core
  /// because the ad-network adapters read it too. Callable before
  /// `configure` (buffered); applied when Attribution starts.
  package nonisolated static func setAdvertisingConsent(_ consent: AdvertisingConsent) {
    guard let reporter = adIdentityHolder.withLock({ $0 }) else {
      pendingAdvertisingConsentHolder.withLock { $0 = consent }
      return
    }
    let hub = adSignalsHolder.withLock { $0 }
    Task {
      await reporter.setConsent(consent)
      await hub?.onConsentChanged()
    }
  }

  /// Ad-signals debug mode: forwarded to the embedded network adapters
  /// (TikTok test events). The public surface is
  /// `AppwinAttribution.setAdSignalsDebugMode`.
  package nonisolated static func setAdSignalsDebugMode(_ enabled: Bool) {
    adSignalsDebugHolder.withLock { $0 = enabled }
  }

  #if os(iOS) && canImport(AppTrackingTransparency)
  /// Convenience ATT prompt. The app decides WHEN to ask (and must
  /// declare `NSUserTrackingUsageDescription` in its Info.plist); this
  /// wrapper only saves the boilerplate and refreshes the identity
  /// report with the answer. Remember the split: a refused ATT does not
  /// stop S2S activation, it only removes the IDFA from it.
  @discardableResult
  package static func requestTrackingAuthorization() async -> Bool {
    let status = await ATTrackingManager.requestTrackingAuthorization()
    if let reporter = adIdentityHolder.withLock({ $0 }) {
      await reporter.start()
    }
    return status == .authorized
  }
  #endif

  /// Test-only: the holders are process-wide, one test would leak into
  /// the next.
  static func resetAdIdentityForTesting() {
    adIdentityHolder.withLock { $0 = nil }
    adSignalsHolder.withLock { $0 = nil }
    conversionValuesHolder.withLock { $0 = nil }
    pendingAdvertisingConsentHolder.withLock { $0 = nil }
  }
}
