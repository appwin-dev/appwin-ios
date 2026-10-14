import Foundation
import AppwinCore

/// Appwin Attribution: the acquisition signals of an app - SKAdNetwork /
/// AdAttributionKit conversion values, the advertising identity (IDFA) and
/// the optional embedded ad-network adapters (TikTok).
///
/// A product in its own right, distinct from Analytics: it has its own
/// `initialize()` and its own dashboard availability. The only thing it
/// shares with Analytics is `AppwinCore`'s event pipeline (the plumbing that
/// ingests events into ClickHouse), which neither product owns.
///
/// No `isReady` gate is needed around the other calls: consent is
/// buffered in any order, and the ATT answer is persisted by iOS - the
/// server verdict decides whether the machinery actually starts.
///
/// ```swift
/// AppwinCore.configure(projectAppId: "…")
/// AppwinAttribution.setAdvertisingConsent(.granted)
/// await AppwinAttribution.initialize()
/// _ = await AppwinAttribution.requestTrackingAuthorization()
/// ```
public enum AppwinAttribution {
  /// Starts the acquisition signals, availability permitting. Call it once
  /// after `AppwinCore.configure`.
  ///
  /// Same contract as the other products: the server verdict (plan, product
  /// toggle) gates the start, the result is cached on disk so an offline
  /// launch falls back to the last known answer, and repeated calls are
  /// cheap.
  @MainActor
  public static func initialize() async -> AppwinInitResult {
    let result = await AppwinCore.availability(of: .attribution)
    isReady = result.isReady
    if !result.isReady {
      AppwinCore.reportUnavailable(.attribution, result)
    } else {
      AppwinCore.startAttribution()
    }
    return result
  }

  /// Whether `initialize()` has returned `.ready`.
  @MainActor
  public private(set) static var isReady = false

  /// Advertising consent (opt-in): whether conversion signals may be
  /// activated towards the ad networks and whether the advertising
  /// identifier (IDFA) may be collected. Relay your consent flow's verdict
  /// here. Callable before `initialize` (buffered).
  ///
  /// The rule: this decides IF signals reach the networks at all; ATT
  /// decides only whether the IDFA enriches them.
  public static func setAdvertisingConsent(_ consent: AdvertisingConsent) {
    AppwinCore.setAdvertisingConsent(consent)
  }

  /// Debug mode for the embedded ad-network adapters (TikTok test
  /// events): events sent while enabled show up in real time in the
  /// network's test console (TikTok Events Manager > Test event) - and
  /// are flagged as TEST data, excluded from campaign optimisation.
  ///
  /// Call it BEFORE `initialize()`: the network SDKs read the flag at
  /// activation and cannot re-init once started. Never ship a release
  /// build with this enabled.
  public static func setAdSignalsDebugMode(_ enabled: Bool) {
    AppwinCore.setAdSignalsDebugMode(enabled)
  }

  #if os(iOS) && canImport(AppTrackingTransparency)
  /// Convenience ATT prompt. The app decides WHEN to ask (and must declare
  /// `NSUserTrackingUsageDescription` in its Info.plist); this wrapper only
  /// saves the boilerplate and refreshes the identity report with the
  /// answer. Remember the split: a refused ATT does not stop S2S
  /// activation, it only removes the IDFA from it.
  @discardableResult
  public static func requestTrackingAuthorization() async -> Bool {
    await AppwinCore.requestTrackingAuthorization()
  }
  #endif
}
