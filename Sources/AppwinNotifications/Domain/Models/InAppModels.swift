import Foundation

public struct InAppMessage: Decodable, Sendable, Identifiable {
  public let id: String
  public let campaignId: String
  public let deliveryId: String
  public let channel: InAppChannel
  public let content: InAppContent
  public let format: InAppFormat
}

public struct InAppContent: Decodable, Sendable {
  public let title: String?
  public let body: String?
  public let imageUrl: String?
  public let deeplink: String?
  public let buttons: [InAppButton]?

  public init(from decoder: Decoder) throws {
    let container = try decoder.container(keyedBy: CodingKeys.self)
    title = try container.decodeIfPresent(String.self, forKey: .title)
    body = try container.decodeIfPresent(String.self, forKey: .body)
    imageUrl = try container.decodeIfPresent(String.self, forKey: .imageUrl)
    deeplink = try container.decodeIfPresent(String.self, forKey: .deeplink)
    buttons = try container.decodeIfPresent([InAppButton].self, forKey: .buttons)
  }

  private enum CodingKeys: String, CodingKey {
    case title, body, imageUrl, deeplink, buttons
  }
}

public struct InAppButton: Decodable, Sendable {
  public let label: String
  public let action: InAppButtonAction
  public let url: String?
}

public enum InAppButtonAction: String, Decodable, Sendable {
  case deeplink
  case dismiss
  case optInPush = "opt_in_push"
  case openSettings = "open_settings"
}

public enum InAppChannel: String, Decodable, Sendable {
  case inApp = "in_app"
  case mobileLanding = "mobile_landing"

  public init(from decoder: Decoder) throws {
    let raw = try decoder.singleValueContainer().decode(String.self)
    guard let value = InAppChannel(rawValue: raw) else {
      throw DecodingError.dataCorrupted(
        .init(codingPath: decoder.codingPath, debugDescription: "Unknown channel: \(raw)")
      )
    }
    self = value
  }
}

public enum InAppFormat: String, Decodable, Sendable {
  case modal
  case banner
  case fullscreen
  case imageOnly = "image_only"

  public init(from decoder: Decoder) throws {
    let raw = try decoder.singleValueContainer().decode(String.self)
    self = InAppFormat(rawValue: raw) ?? .modal
  }
}

public enum TrackEvent: String, Sendable {
  case opened, clicked, dismissed
}

public enum AutomationEvent: String, Sendable {
  case appOpen = "app_open"
  case appBackground = "app_background"
  case purchase
  case customEvent = "custom_event"
  case pushOptIn = "push_opt_in"
  case sessionStart = "session_start"
}

public enum AppwinNotificationsError: Error {
  case notConfigured
  case pushNotAuthorized
}
