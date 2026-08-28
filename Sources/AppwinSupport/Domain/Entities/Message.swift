// Domain entity shaped by the app, not the API: it keeps only what a chat
// bubble has to display. `conversationId` and `authorId` exist on `MessageDTO`
// but do not surface here until a screen needs them.

import Foundation

struct Message: Identifiable, Equatable {
    let id: String
    /// Drives bubble alignment and colour: us versus the studio.
    let authorType: MessageAuthorType
    /// Display name for studio messages (`authorNameSnapshot` server-side).
    let authorName: String?
    let body: String
    /// `nil` means unread.
    let readAt: Date?
    let createdAt: Date
    /// Images and files; `[]` when there are none.
    let attachments: [Attachment]
    /// Aggregated emoji reactions, mirroring `MessageReactionSummary`.
    let reactions: [MessageReaction]
}

/// Aggregated reaction on a message.
struct MessageReaction: Identifiable, Equatable {
    var id: String { emoji }
    let emoji: String
    let count: Int
    let reactedByMe: Bool
}

/// Mirrors the server's `MessageAuthorTypeSchema`.
enum MessageAuthorType: String, Equatable {
    case customer
    /// Studio member; the wire value is `organization_member`.
    case organizationMember = "organization_member"
    /// Autonomous AI reply, rendered on the studio side.
    case aiAssistant = "ai_assistant"

    /// Message from the studio, human or AI.
    var isStudio: Bool {
        switch self {
        case .organizationMember, .aiAssistant: return true
        case .customer: return false
        }
    }
}

/// Same set as the dashboard's `QUICK_COMMENT_REACTIONS`.
enum QuickMessageReactions {
    static let all: [String] = ["👍", "🔥", "❤️", "😂", "😮", "🎉"]
}
