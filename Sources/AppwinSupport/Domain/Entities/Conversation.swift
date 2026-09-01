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
    /// Last read by the customer; drives the unread badge.
    let lastReadAt: Date?
    let createdAt: Date
}

/// Mirrors the server's `ConversationStatusSchema`.
enum ConversationStatus: String {
    case open
    case resolved
    case closed
}
