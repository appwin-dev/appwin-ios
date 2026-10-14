import Foundation

/// Locale used for SDK UI strings and date stamps.
///
/// UI chrome follows the **device** preferred languages (not `Locale.current`,
/// which on Flutter / RN hosts often mirrors the app's only localization,
/// typically English). An explicit `languageCode` still wins when the studio
/// or host sets it on purpose.
public enum AppwinDisplayLocale {
  public static func locale(languageCode: String?, fallback: Locale = .current) -> Locale {
    if let raw = normalize(languageCode) {
      return Locale(identifier: raw)
    }
    return deviceLocale(fallback: fallback)
  }

  /// Language tag for UI strings. Prefer an explicit code; otherwise the
  /// device preferred language (SDK `fr.lproj` / `en.lproj`).
  public static func uiLanguage(customerLanguage: String?) -> String? {
    if let raw = normalize(customerLanguage) {
      return String(raw.prefix(2))
    }
    return deviceLanguageCode()
  }

  /// Picks the matching `*.lproj` inside an SDK resource bundle.
  public static func bundle(languageCode: String?, resources: Bundle) -> Bundle {
    let resolved = languageCode.flatMap(normalize) ?? deviceLanguageCode()
    if let raw = resolved {
      return lprojBundle(in: resources, codes: [raw, String(raw.prefix(2))]) ?? resources
    }
    let preferred = Bundle.preferredLocalizations(
      from: resources.localizations,
      forPreferences: Locale.preferredLanguages
    )
    return lprojBundle(in: resources, codes: preferred) ?? resources
  }

  public static func deviceLanguageCode() -> String? {
    guard let preferred = Locale.preferredLanguages.first else { return nil }
    return normalize(preferred).map { String($0.prefix(2)) }
  }

  private static func deviceLocale(fallback: Locale) -> Locale {
    if let code = deviceLanguageCode() {
      return Locale(identifier: code)
    }
    return fallback
  }

  private static func lprojBundle(in resources: Bundle, codes: [String]) -> Bundle? {
    for code in codes {
      if let path = resources.path(forResource: code, ofType: "lproj"),
         let bundle = Bundle(path: path) {
        return bundle
      }
    }
    return nil
  }

  private static func normalize(_ languageCode: String?) -> String? {
    let trimmed = languageCode?
      .trimmingCharacters(in: .whitespacesAndNewlines)
      .replacingOccurrences(of: "_", with: "-")
      .lowercased()
    guard let trimmed, !trimmed.isEmpty else { return nil }
    return trimmed
  }
}
