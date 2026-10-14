import Foundation

/// Contract an ad-network adapter module implements (ADR-0038, revised
/// 2026-09-05: the TikTok App Events SDK ships as an internal adapter
/// of the appwin SDK, in its own optional module). The studio never
/// touches this: adding the SPM product to the app is the whole
/// integration, Core discovers it through the ObjC runtime and drives
/// its lifecycle.
///
/// Rules the implementation must honour:
/// - activate only ever fires with the advertising consent granted AND
///   the network wired in the dashboard (remote config);
/// - the adapter's own SKAN handling stays disabled - Core v2 is the
///   single conversion-value manager;
/// - onEvent receives the SAME eventId our ingest stores, so the
///   network can dedupe against any server-side source of the event.
public protocol AdSignalsAdapter: AnyObject, Sendable {
  /// Network key, matching the dashboard destination ('tiktok').
  var network: String { get }

  /// Config = the dashboard-declared wiring for this app.
  func activate(config: [String: String])

  /// Consent withdrawn or network unwired: stop emitting.
  func deactivate()

  func onEvent(name: String, eventId: String, props: [String: AnalyticsValue]?)
}

/// Swift has no ServiceLoader: adapter modules expose an @objc-named
/// NSObject subclass conforming to this, and Core probes the known
/// names through NSClassFromString (the Firebase-style discovery - the
/// linker only finds it when the app actually ships the module).
@objc public protocol AdSignalsAdapterProvider {
  init()
  func makeAdapter() -> AnyObject
}

/// Stable ObjC names Core probes at start; one per adapter module.
let AD_SIGNALS_PROVIDER_NAMES = ["AppwinTikTokEventsAdapterProvider"]

func loadAdSignalsAdapters() -> [AdSignalsAdapter] {
  AD_SIGNALS_PROVIDER_NAMES.compactMap { name in
    guard let cls = NSClassFromString(name) as? (NSObject & AdSignalsAdapterProvider).Type else {
      return nil
    }
    return cls.init().makeAdapter() as? AdSignalsAdapter
  }
}
