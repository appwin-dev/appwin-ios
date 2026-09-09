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
    let appId = config["storeAppId"] ?? Bundle.main.bundleIdentifier ?? ""
    guard let ttConfig = TikTokConfig(
      accessToken: accessToken, appId: appId, tiktokAppId: tiktokAppId)
    else { return }
    ttConfig.disableSKAdNetworkSupport()
    TikTokBusiness.initializeSdk(ttConfig)
    lock.lock()
    running = true
    lock.unlock()
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
