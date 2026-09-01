import Foundation

enum NotificationsStrings {
  static var ctaOpen: String {
    Bundle.main.preferredLocalizations.first?.hasPrefix("fr") == true ? "Ouvrir" : "Open"
  }
}
