// Shared DTO tooling: ISO date parsing and the mapping error. Lives in Infra;
// the domain knows nothing about any of it.

import Foundation

/// Raised when a network DTO cannot become a domain entity.
enum DTOMappingError: Error {
    /// A required ISO date is missing or unparsable.
    case invalidDate(field: String, value: String)
    /// Enum value unknown to the SDK, meaning contract drift with the server.
    case unknownValue(field: String, value: String)
}

/// Parses the ISO 8601 dates the API returns, tolerating milliseconds being
/// present or absent (`2024-01-15T10:30:00.000Z` or `2024-01-15T10:30:00Z`).
enum ISODate {
    // `Date.ISO8601FormatStyle` is a `Sendable` value type with no shared
    // mutable state, so it is safe as a `static let` with no `unsafe`.
    private static let withFractional = Date.ISO8601FormatStyle(includingFractionalSeconds: true)
    private static let plain          = Date.ISO8601FormatStyle(includingFractionalSeconds: false)

    /// Optional variant: `nil` when the string is nil or unparsable.
    static func date(_ string: String?) -> Date? {
        guard let string else { return nil }
        return (try? withFractional.parse(string)) ?? (try? plain.parse(string))
    }

    /// Required variant: throws `DTOMappingError.invalidDate` on failure.
    static func requiredDate(_ string: String, field: String) throws -> Date {
        guard let date = date(string) else {
            throw DTOMappingError.invalidDate(field: field, value: string)
        }
        return date
    }
}
