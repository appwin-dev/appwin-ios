import Foundation

enum NotificationsStrings {
  private static func t(_ key: String, _ fallback: String) -> String {
    let host = NSLocalizedString(key, tableName: "AppwinNotifications", bundle: .main, value: "", comment: "")
    if host != key && !host.isEmpty { return host }
    return NSLocalizedString(
      key,
      tableName: "AppwinNotifications",
      bundle: resourceBundle,
      value: fallback,
      comment: ""
    )
  }

  private static var resourceBundle: Bundle {
    #if SWIFT_PACKAGE
    .module
    #else
    Bundle.appwinNotificationsResources
    #endif
  }

  static var ctaOpen: String { t("notifications.cta_open", "Open") }
}

#if !SWIFT_PACKAGE
private final class AppwinNotificationsBundleToken {}

extension Bundle {
  static let appwinNotificationsResources: Bundle = {
    let candidates: [URL?] = [
      Bundle(for: AppwinNotificationsBundleToken.self).resourceURL,
      Bundle.main.resourceURL,
      Bundle.main.bundleURL,
    ]
    for base in candidates.compactMap({ $0 }) {
      let url = base.appendingPathComponent("AppwinNotifications.bundle")
      if let bundle = Bundle(url: url) { return bundle }
    }
    return Bundle(for: AppwinNotificationsBundleToken.self)
  }()
}
#endif
