import Foundation

/// Persisted GDPR consent, one state per purpose, cached in memory. Per
/// install on purpose: prefs (not Keychain) so a reinstall starts back at the
/// default.
///
/// Every purpose defaults to `granted` (opt-out, the PostHog model): most
/// studios fall under the first-party audience-measurement exemption and
/// expect analytics to work out of the box. A studio with a consent screen
/// sets `unknown` before it and relays the answer.
///
/// The prefs are the single source of truth, read and written under one
/// process-wide lock (`setConsent` writes from the caller's thread, the
/// pipeline reads from its actor, the legacy migration does both): the store
/// holds no cache that could drift from them.
final class ConsentStore {
  private let prefs: AnalyticsPrefs
  private let keyPrefix: String
  private static let lock = NSLock()

  /// `initial` are consents set BEFORE `configure` (a consent-screen studio
  /// starting in `unknown`), in call order: applied synchronously here, so no
  /// event can slip out between the pipeline's creation and an async
  /// setConsent.
  init(
    prefs: AnalyticsPrefs, keyPrefix: String,
    initial: [(ConsentState, ConsentPurpose?)] = []
  ) {
    self.prefs = prefs
    self.keyPrefix = keyPrefix
    for (state, purpose) in initial { set(state, for: purpose) }
  }

  /// 0.15.0 kept one consent for everything under this key.
  private static let legacyKeySuffix = "consent"

  private static func key(_ keyPrefix: String, _ purpose: ConsentPurpose) -> String {
    keyPrefix + "consent." + purpose.rawValue
  }

  /// The persisted value, readable from any thread.
  static func stored(prefs: AnalyticsPrefs, keyPrefix: String, purpose: ConsentPurpose) -> ConsentState {
    lock.lock()
    defer { lock.unlock() }
    migrateLegacy(prefs: prefs, keyPrefix: keyPrefix)
    return prefs.string(forKey: key(keyPrefix, purpose)).flatMap(ConsentState.init(rawValue:)) ?? .granted
  }

  /// Persists synchronously. `nil` sets the three at once.
  static func write(
    prefs: AnalyticsPrefs, keyPrefix: String, _ state: ConsentState, for purpose: ConsentPurpose?
  ) {
    lock.lock()
    defer { lock.unlock() }
    // Before the write, or the legacy value would later fill what was just answered.
    migrateLegacy(prefs: prefs, keyPrefix: keyPrefix)
    for target in purpose.map({ [$0] }) ?? ConsentPurpose.allCases {
      prefs.set(state.rawValue, forKey: key(keyPrefix, target))
    }
  }

  /// Caller holds the lock. An app that refused consent in 0.15.0 stays
  /// refused on the three: the old value is copied to every purpose without
  /// an answer, then dropped.
  private static func migrateLegacy(prefs: AnalyticsPrefs, keyPrefix: String) {
    let legacyKey = keyPrefix + legacyKeySuffix
    guard let legacy = prefs.string(forKey: legacyKey) else { return }
    for purpose in ConsentPurpose.allCases where prefs.string(forKey: key(keyPrefix, purpose)) == nil {
      prefs.set(legacy, forKey: key(keyPrefix, purpose))
    }
    prefs.set(nil, forKey: legacyKey)
  }

  func state(for purpose: ConsentPurpose) -> ConsentState {
    Self.stored(prefs: prefs, keyPrefix: keyPrefix, purpose: purpose)
  }

  /// `nil` sets the three at once.
  func set(_ newValue: ConsentState, for purpose: ConsentPurpose?) {
    Self.write(prefs: prefs, keyPrefix: keyPrefix, newValue, for: purpose)
  }

  var grantedPurposes: [ConsentPurpose] {
    ConsentPurpose.allCases.filter { state(for: $0) == .granted }
  }

  var allDenied: Bool { ConsentPurpose.allCases.allSatisfy { state(for: $0) == .denied } }

  var anyUnknown: Bool { ConsentPurpose.allCases.contains { state(for: $0) == .unknown } }
}
