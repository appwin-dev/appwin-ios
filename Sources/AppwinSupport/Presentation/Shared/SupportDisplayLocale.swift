import Foundation
import AppwinCore

/// Locale used for messenger date stamps and day labels.
///
/// Thin wrapper over [AppwinDisplayLocale] so Support call sites keep a
/// product-scoped name.
enum SupportDisplayLocale {
  static func locale(languageCode: String?, fallback: Locale = .current) -> Locale {
    AppwinDisplayLocale.locale(languageCode: languageCode, fallback: fallback)
  }

  static func uiLanguage(customerLanguage: String?) -> String? {
    AppwinDisplayLocale.uiLanguage(customerLanguage: customerLanguage)
  }

  static func bundle(languageCode: String?, resources: Bundle) -> Bundle {
    AppwinDisplayLocale.bundle(languageCode: languageCode, resources: resources)
  }

  static func deviceLanguageCode() -> String? {
    AppwinDisplayLocale.deviceLanguageCode()
  }
}
