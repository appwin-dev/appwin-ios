// Raw network mirror of `MessageSchema` (packages/contracts): every field,
// dates as `String`, authorType as `String`. `toDomain()` converts it to the
// trimmed `Message` entity.

import Foundation

struct MessageDTO: Codable {
    let id: String
    let conversationId: String
    let authorType: String
    let authorId: String
    let authorNameSnapshot: String?
    let body: String
    let readAt: String?
    let createdAt: String
    /// Optional for decoding robustness: always present server-side, but one
    /// message missing it must not break the whole list.
    let attachments: [AttachmentDTO]?
    let reactions: [MessageReactionDTO]?
}

struct MessageReactionDTO: Codable {
    let emoji: String
    let count: Int
    let reactedByMe: Bool
}

extension MessageDTO {
    /// Network to domain. `authorNameSnapshot` becomes `authorName`;
    /// `conversationId` and `authorId` are dropped, being unused on screen for
    /// now.
    func toDomain() throws -> Message {
        // Unknown values map to studio, so the thread does not break if the API
        // adds an authorType before the SDK is rebuilt.
        let authorTypeEnum =
            MessageAuthorType(rawValue: authorType) ?? .organizationMember
        return Message(
            id: id,
            authorType: authorTypeEnum,
            authorName: authorNameSnapshot,
            body: body,
            readAt: ISODate.date(readAt),
            createdAt: try ISODate.requiredDate(createdAt, field: "createdAt"),
            attachments: try (attachments ?? []).map { try $0.toDomain() },
            reactions: (reactions ?? []).map {
                MessageReaction(emoji: $0.emoji, count: $0.count, reactedByMe: $0.reactedByMe)
            }
        )
    }
}
