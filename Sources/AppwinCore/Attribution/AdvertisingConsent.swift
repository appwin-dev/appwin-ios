import Foundation

/// Consent for the advertising destination (ADR-0038): whether event
/// signals may be activated towards ad networks (Meta CAPI, TikTok) and
/// whether the device advertising identifier may be collected.
///
/// Opt-in, unlike analytics: advertising has no audience-measurement
/// exemption, so nothing is collected or forwarded until the studio
/// relays an explicit `granted` from its consent flow. Note the split
/// with ATT: this consent decides IF signals flow to networks at all,
/// ATT only decides whether the IDFA enriches them (refused ATT still
/// sends, at a lower match quality).
public enum AdvertisingConsent: Sendable {
  case granted
  case denied
  case unknown
}
