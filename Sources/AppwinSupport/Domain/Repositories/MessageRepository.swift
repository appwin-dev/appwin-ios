import Foundation

protocol MessageRepository: Sendable {
  func getAll(conversationId: String, cursor: String?, limit: Int) async throws -> CursorPaginated<Message>
  func send(conversationId: String, body: String, attachments: [AttachmentInput]) async throws -> Message
  /// Edits the body of one of the customer's own messages, enforced server-side.
  func update(conversationId: String, messageId: String, body: String) async throws -> Message
  /// Deletes one of the customer's own messages, enforced server-side.
  func delete(conversationId: String, messageId: String) async throws
  /// Marks the studio's messages as read.
  func markRead(conversationId: String) async throws
  /// Mints a fresh signed GET URL for an attachment, on tap: the one captured
  /// at load time expires after 15 minutes.
  func freshAttachmentURL(attachmentId: String) async throws -> URL
  /// Toggles an emoji reaction.
  func toggleReaction(conversationId: String, messageId: String, emoji: String) async throws -> Message
}
