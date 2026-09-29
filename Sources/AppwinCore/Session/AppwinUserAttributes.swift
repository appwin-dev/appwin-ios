import Foundation

/// Attributes of the person using the app, shared by every Appwin product.
///
/// Pass them to `AppwinCore.identify(externalId:attributes:)` or
/// `AppwinCore.updateUser(_:)`. Every field is optional: a `nil` field is not
/// sent, so the value already known server-side is left untouched. Device
/// attributes (model, OS, app version) are collected by the SDK itself.
public struct AppwinUserAttributes: Sendable, Encodable, Equatable {
  public var email: String?
  public var name: String?
  public var avatarUrl: String?
  /// ISO 639-1 code (`"fr"`, `"en"`).
  public var language: String?
  /// IANA time zone identifier (`"Europe/Paris"`).
  public var timezone: String?
  public var location: String?
  /// The host app's own plan or tier label, usable for segmentation.
  public var plan: String?

  public init(
    email: String? = nil,
    name: String? = nil,
    avatarUrl: String? = nil,
    language: String? = nil,
    timezone: String? = nil,
    location: String? = nil,
    plan: String? = nil
  ) {
    self.email = email
    self.name = name
    self.avatarUrl = avatarUrl
    self.language = language
    self.timezone = timezone
    self.location = location
    self.plan = plan
  }
}
