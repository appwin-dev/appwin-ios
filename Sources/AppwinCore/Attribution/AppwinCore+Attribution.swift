import Foundation
import os
#if os(iOS) && canImport(AppTrackingTransparency)
import AppTrackingTransparency
#endif

private let adIdentityHolder = OSAllocatedUnfairLock<AdIdentityReporter?>(initialState: nil)
private let adSignalsHolder = OSAllocatedUnfairLock<AdSignalsHub?>(initialState: nil)

/// Same buffering story as the analytics consent, advertising side: a
/// consent-screen studio may answer before the runtime exists.
private let pendingAdvertisingConsentHolder =
  OSAllocatedUnfairLock<AdvertisingConsent?>(initialState: nil)

extension AppwinCore {
  // MARK: - Advertising identity (ADR-0038, S2S activation)

  /// Wired from `startAnalytics`: the identity report needs the bearer
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
      consent: { AdIdentityReporter.storedConsent(prefs: prefs, keyPrefix: keyPrefix) })
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
  /// advertising identifier. Cross-product infrastructure like
  /// `configure`, not a product API - the future TikTok adapter reads
  /// the same switch. Callable before `configure` (buffered); applied
  /// when the analytics runtime starts.
  public nonisolated static func setAdvertisingConsent(_ consent: AdvertisingConsent) {
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

  #if os(iOS) && canImport(AppTrackingTransparency)
  /// Convenience ATT prompt. The app decides WHEN to ask (and must
  /// declare `NSUserTrackingUsageDescription` in its Info.plist); this
  /// wrapper only saves the boilerplate and refreshes the identity
  /// report with the answer. Remember the split: a refused ATT does not
  /// stop S2S activation, it only removes the IDFA from it.
  @discardableResult
  public static func requestTrackingAuthorization() async -> Bool {
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
    pendingAdvertisingConsentHolder.withLock { $0 = nil }
  }
}
