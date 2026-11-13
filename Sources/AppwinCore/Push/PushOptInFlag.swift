import Foundation

/// The "push opt-in already reported" mark and the decision to report.
///
/// `push_opt_in` leaves once per installation, and only for an opt-in the SDK
/// witnessed: a fresh install, or a grant seen in this process. An app that
/// upgrades with users already opted in must not announce them all as new
/// opt-ins (a journey triggered on `push_opt_in` would fire for the whole
/// user base): for them the mark is set silently.
enum PushOptInFlag {
  private static let keySuffix = "pushOptIn.tracked"

  static func shouldEmit(freshInstall: Bool, grantedThisProcess: Bool, alreadyClaimed: Bool) -> Bool {
    !alreadyClaimed && (freshInstall || grantedThisProcess)
  }

  /// Sets the mark if it was not; true when the event must be emitted.
  static func claim(
    prefs: AnalyticsPrefs, keyPrefix: String, freshInstall: Bool, grantedThisProcess: Bool
  ) -> Bool {
    let key = keyPrefix + keySuffix
    let alreadyClaimed = prefs.string(forKey: key) != nil
    if !alreadyClaimed { prefs.set("1", forKey: key) }
    return shouldEmit(
      freshInstall: freshInstall, grantedThisProcess: grantedThisProcess,
      alreadyClaimed: alreadyClaimed)
  }
}
