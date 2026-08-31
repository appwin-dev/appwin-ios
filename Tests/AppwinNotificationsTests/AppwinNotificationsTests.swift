import Foundation
import Testing
@testable import AppwinNotifications

/// These tests cover the **wire values**.
///
/// The server validates events on their `snake_case` form. A constant renamed on
/// the Swift side would compile without complaint and silently break every
/// automation - exactly the kind of mistake no compiler catches.
struct AppwinNotificationsTests {

  @Test("Les événements d'automatisation portent leur valeur serveur")
  func automationEventWireValues() {
    #expect(AutomationEvent.appOpen.rawValue == "app_open")
    #expect(AutomationEvent.appBackground.rawValue == "app_background")
    #expect(AutomationEvent.purchase.rawValue == "purchase")
    #expect(AutomationEvent.customEvent.rawValue == "custom_event")
    #expect(AutomationEvent.pushOptIn.rawValue == "push_opt_in")
    #expect(AutomationEvent.sessionStart.rawValue == "session_start")
  }

  @Test("Les événements de suivi portent leur valeur serveur")
  func trackEventWireValues() {
    #expect(TrackEvent.opened.rawValue == "opened")
    #expect(TrackEvent.clicked.rawValue == "clicked")
    #expect(TrackEvent.dismissed.rawValue == "dismissed")
  }

  @Test("Un message in-app se décode depuis la réponse serveur")
  func decodesInAppMessage() throws {
    let json = """
    {
      "id": "m1",
      "campaignId": "c1",
      "deliveryId": "d1",
      "channel": "in_app",
      "format": "modal",
      "content": { "title": "Salut", "body": "Nouveauté", "futureField": 42 }
    }
    """.data(using: .utf8)!

    let message = try JSONDecoder().decode(InAppMessage.self, from: json)

    #expect(message.id == "m1")
    #expect(message.content.title == "Salut")
    // A field added server-side must not break binaries already installed on
    // phones, which we cannot update.
    #expect(message.content.imageUrl == nil)
  }
}
