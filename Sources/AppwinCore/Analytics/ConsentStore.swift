import Foundation

/// Persisted GDPR consent, cached in memory. Per install on purpose: prefs
/// (not Keychain) so a reinstall starts back at the default.
///
/// Defaults to `granted` (opt-out, the PostHog model): most studios fall
/// under the first-party audience-measurement exemption and expect analytics
/// to work out of the box. A studio with a consent screen sets `unknown`
/// before it and relays the answer.
final class ConsentStore {
  private let prefs: AnalyticsPrefs
  private let key: String
  private(set) var consent: AnalyticsConsent

  /// `initial` is a consent set BEFORE `configure` (a consent-screen studio
  /// starting in `unknown`): applied synchronously here, so no event can
  /// slip out between the pipeline's creation and an async setConsent.
  init(prefs: AnalyticsPrefs, keyPrefix: String, initial: AnalyticsConsent? = nil) {
    self.prefs = prefs
    self.key = keyPrefix + "consent"
    self.consent = prefs.string(forKey: key).flatMap(AnalyticsConsent.init(rawValue:)) ?? .granted
    if let initial, initial != consent { set(initial) }
  }

  func set(_ newValue: AnalyticsConsent) {
    consent = newValue
    prefs.set(newValue.rawValue, forKey: key)
  }
}
