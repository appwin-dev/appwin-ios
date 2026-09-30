// Raw network mirror of `ConversationSchema` (packages/contracts): every field,
// dates as `String`, status as `String`. This is the `Codable` type, because
// serialisation is an Infra concern. `toDomain()` converts it to the trimmed
// `Conversation` entity.

import Foundation

struct ConversationDTO: Codable {
    let id: String
    let orgId: String
    let projectId: String
    let customerId: String
    let preview: String?
    let status: String
    let isUrgent: Bool
    let isFavorite: Bool
    let isSpam: Bool
    let lastMessageAt: String?
    let lastMessageAuthorType: String?
    let lastReadAt: String?
    let resolvedAt: String?
    let closedAt: String?
    let participantIds: [String]
    let tagIds: [String]
    let createdAt: String
    let updatedAt: String
}

extension ConversationDTO {
    /// Network to domain. Converts strings to dates and enums, and drops the
    /// fields the app does not use (orgId, isSpam, tagIds, …).
    func toDomain() throws -> Conversation {
        guard let statusEnum = ConversationStatus(rawValue: status) else {
            throw DTOMappingError.unknownValue(field: "status", value: status)
        }
        return Conversation(
            id: id,
            preview: preview,
            status: statusEnum,
            lastMessageAt: ISODate.date(lastMessageAt),
            // Unknown values are dropped rather than thrown on: a new author
            // type added server-side must not break the conversation list.
            lastMessageAuthorType: lastMessageAuthorType.flatMap(MessageAuthorType.init(rawValue:)),
            lastReadAt: ISODate.date(lastReadAt),
            createdAt: try ISODate.requiredDate(createdAt, field: "createdAt")
        )
    }
}
