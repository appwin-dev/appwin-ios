import Foundation
import AppwinCore
import TikTokBusinessSDK

/// TikTok App Events adapter (ADR-0038, exception acted 2026-09-05):
/// wraps the official TikTok Business SDK behind the appwin surface -
/// the studio only ever calls track(), Core drives this through the
/// ad-signals hub (advertising consent + dashboard wiring).
///
/// Governance choices, per the ADR contract:
/// - `disableSKAdNetworkSupport`: Core v2 is the SINGLE conversion
///   value manager, the TikTok SDK must never touch SKAN.
/// - Auto install/launch tracking stays ON: those are TikTok's own
///   attribution signals and the adapter only ever runs under consent.
/// - Every relayed event carries the SAME event_id as our ingest, so a
///   future server-side Events API source dedupes within TikTok's 48 h
///   window.
/// - The TikTok SDK cannot be un-initialized: after a deactivate
///   (consent withdrawn mid-session) we stop relaying, and the next
///   launch simply never activates it.
final class TikTokAdSignalsAdapter: AdSignalsAdapter, @unchecked Sendable {
  let network = "tiktok"

  private let lock = NSLock()
  private var running = false

  func activate(config: [String: String]) {
    guard let tiktokAppId = config["appId"], let accessToken = config["accessToken"] else { return }
    // The TikTok SDK regex-validates its appId as the NUMERIC App Store
    // id and silently refuses to init otherwise - never fall back to
    // the bundle id. Served from the project's App Store integration.
    guard let appId = config["storeAppId"], appId.allSatisfy(\.isNumber), !appId.isEmpty else {
      NSLog("[Appwin][TikTok] missing numeric storeAppId (App Store id), adapter not activated")
      return
    }
    // The hub reconciles on an actor (background executor), but the
    // TikTok SDK must init on the MAIN thread: it schedules runloop
    // timers and loads a WKWebView for the user agent - off-main its
    // remote-switch fetch silently never resolves and nothing is ever
    // flushed.
    DispatchQueue.main.async { [weak self] in
      guard let self else { return }
      guard let ttConfig = TikTokConfig(
        accessToken: accessToken, appId: appId, tiktokAppId: tiktokAppId)
      else { return }
      ttConfig.disableSKAdNetworkSupport()
      // Same governance as SKAN: our relayed `purchase` (with our
      // event_id) is the single purchase signal. TikTok's own StoreKit
      // observer would double-count it under an id nobody can dedupe.
      // Android needs no equivalent: their auto-IAP is opt-in.
      ttConfig.disablePaymentTracking()
      // Test-events mode (AppwinAttribution.setAdSignalsDebugMode):
      // events stream to the Events Manager test console and are
      // excluded from campaign optimisation.
      if config["debugMode"] == "true" {
        ttConfig.enableDebugMode()
        // Debug implies chatty: surface the network SDK's own
        // diagnostics (delivery failures are otherwise swallowed).
        ttConfig.setLogLevel(TikTokLogLevelVerbose)
      }
      TikTokBusiness.initializeSdk(ttConfig) { success, error in
        // Surfaces silent init failures (invalid ids, tracking off);
        // the TikTok SDK otherwise swallows them entirely.
        if !success {
          NSLog("[Appwin][TikTok] init failed: %@", error?.localizedDescription ?? "unknown")
        } else {
          NSLog("[Appwin][TikTok] init OK")
        }
      }
      self.lock.lock()
      self.running = true
      self.lock.unlock()
    }
  }

  func deactivate() {
    lock.lock()
    running = false
    lock.unlock()
  }

  func onEvent(name: String, eventId: String, props: [String: AnalyticsValue]?) {
    lock.lock()
    let isRunning = running
    lock.unlock()
    guard isRunning else { return }
    let event = TikTokBaseEvent(eventName: mapEventName(name), eventId: eventId)
    if let props {
      for (key, value) in props {
        event.addProperty(withKey: key, value: value.jsonValue)
      }
    }
    TikTokBusiness.trackTTEvent(event)
  }
}

/// Our lower_snake names to TikTok's standard app event names; anything
/// else forwards under its own (custom) name.
func mapEventName(_ name: String) -> String {
  switch name {
  case "purchase": "Purchase"
  case "start_trial": "StartTrial"
  case "subscribe": "Subscribe"
  case "complete_registration": "CompleteRegistration"
  default: name
  }
}

/// Discovery entry Core probes through NSClassFromString - adding the
/// AppwinTikTokEvents product to the app is the whole integration.
@objc(AppwinTikTokEventsAdapterProvider)
public final class AppwinTikTokEventsAdapterProvider: NSObject, AdSignalsAdapterProvider {
  override public required init() {
    super.init()
  }

  public func makeAdapter() -> AnyObject {
    TikTokAdSignalsAdapter()
  }
}
