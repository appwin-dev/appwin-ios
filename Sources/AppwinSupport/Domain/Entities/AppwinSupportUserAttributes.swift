// Public attribute bag the integrating app fills on `loginIdentifiedUser`, the
// modern value-type equivalent of Intercom's `ICMUserAttributes`. It holds only
// the person's traits; device traits (model, os, appVersion) are filled in
// automatically by the SDK.
//
// Every field is optional, with PATCH semantics server-side.
public struct AppwinSupportUserAttributes {
    public var email: String?
    public var name: String?
    public var avatarUrl: String?
    public var language: String?
    public var timezone: String?
    public var location: String?

    public init(
        email: String? = nil,
        name: String? = nil,
        avatarUrl: String? = nil,
        language: String? = nil,
        timezone: String? = nil,
        location: String? = nil,
    ) {
        self.email = email
        self.name = name
        self.avatarUrl = avatarUrl
        self.language = language
        self.timezone = timezone
        self.location = location
    }
}
