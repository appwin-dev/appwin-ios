// Domain entity shaped by the app, not the API: it keeps only what the
// messenger displays. Server fields (orgId, isUrgent, isSpam, participantIds,
// tagIds, resolvedAt, …) stay on `ConversationDTO` until a screen needs them.

import Foundation

struct Conversation: Identifiable, Hashable {
    let id: String
    /// Last message preview, for the conversation list.
    let preview: String?
    let status: ConversationStatus
    /// Sorts the list.
    let lastMessageAt: Date?
    /// Who wrote last, `nil` on an empty conversation.
    ///
    /// What tells an inbound reply from the customer's own message without
    /// fetching the thread - the in-app banner needs exactly that distinction.
    let lastMessageAuthorType: MessageAuthorType?
    /// Last read by the customer; drives the unread badge with [hasUnread].
    let lastReadAt: Date?
    let createdAt: Date

    /// True when support wrote after the customer last read - not when the
    /// customer themselves sent the latest message.
    var hasUnread: Bool {
        guard lastMessageAuthorType?.isStudio == true else { return false }
        guard let lastMessageAt else { return false }
        guard let lastReadAt else { return true }
        return lastMessageAt > lastReadAt
    }
}

/// Mirrors the server's `ConversationStatusSchema`.
enum ConversationStatus: String {
    case open
    case resolved
    case closed
}
