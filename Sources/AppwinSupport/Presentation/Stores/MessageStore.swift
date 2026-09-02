
import Foundation

@MainActor
class MessageStore: ObservableObject {
  private let getAllMessageUsecase: GetAllMessagesUseCase
  private let sendMessageUsecase: SendMessageUseCase
  private let markMessagesReadUsecase: MarkMessagesReadUseCase
  private let refreshAttachmentURLUseCase: RefreshAttachmentURLUseCase
  private let updateMessageUsecase: UpdateMessageUseCase
  private let deleteMessageUsecase: DeleteMessageUseCase
  private let toggleReactionUsecase: ToggleMessageReactionUseCase

  @Published var messages: [Message] = []
  @Published var isLoading: Bool = false
  @Published var errorLoadMessages: Error?
  @Published var errorSendMessage: Error?
  /// `true` while older messages remain to load, scrolling up.
  @Published var hasMoreOlder = false
  /// Agent currently typing, from the realtime `support.typing` event.
  @Published var peerIsTyping = false
  /// Messages loaded per fetch.
  private let pageLimit = 30
  /// Cursor for older messages. `nil` means the whole history is loaded.
  private var olderCursor: String?
  /// Conversation currently loaded, so `loadOlderMessages()` resumes on the
  /// right one without the view passing the id again.
  private(set) var currentConversationId: String?
  /// Guards against concurrent reloads: the scroll sentinel's `.onAppear` can
  /// fire several times in a row.
  private var isLoadingOlder = false
  private var typingClearTask: Task<Void, Never>?

  init(
    getAllMessageUsecase: GetAllMessagesUseCase,
    sendMessageUsecase: SendMessageUseCase,
    markMessagesReadUsecase: MarkMessagesReadUseCase,
    refreshAttachmentURLUseCase: RefreshAttachmentURLUseCase,
    updateMessageUsecase: UpdateMessageUseCase,
    deleteMessageUsecase: DeleteMessageUseCase,
    toggleReactionUsecase: ToggleMessageReactionUseCase,
    messages: [Message]
  ) {
    self.getAllMessageUsecase = getAllMessageUsecase
    self.sendMessageUsecase = sendMessageUsecase
    self.markMessagesReadUsecase = markMessagesReadUsecase
    self.refreshAttachmentURLUseCase = refreshAttachmentURLUseCase
    self.updateMessageUsecase = updateMessageUsecase
    self.deleteMessageUsecase = deleteMessageUsecase
    self.toggleReactionUsecase = toggleReactionUsecase
    self.messages = messages
  }

  /// Applies an agent typing event, ignored when it targets another conversation.
  func applyPeerTyping(conversationId: String?, isTyping: Bool) {
    guard let conversationId,
          conversationId == currentConversationId else { return }
    typingClearTask?.cancel()
    peerIsTyping = isTyping
    if isTyping {
      typingClearTask = Task {
        try? await Task.sleep(nanoseconds: 3_000_000_000)
        guard !Task.isCancelled else { return }
        peerIsTyping = false
      }
    }
  }

  /// Fresh signed URL to open an attachment, re-signed on tap.
  func freshAttachmentURL(attachmentId: String) async throws -> URL {
    try await refreshAttachmentURLUseCase.execute(attachmentId: attachmentId)
  }

  /// New conversation with no id yet: clears the shared thread.
  func resetForNewConversation() {
    messages = []
    errorLoadMessages = nil
    errorSendMessage = nil
    currentConversationId = nil
    peerIsTyping = false
    typingClearTask?.cancel()
    olderCursor = nil
    hasMoreOlder = false
    isLoading = false
  }
  
  func loadMessages(conversationId:String) async throws{
    isLoading = true
    messages = []            // vide l'ancienne conversation → on ne la voit plus pendant le chargement
    errorLoadMessages = nil  // reset l'erreur d'un éventuel chargement précédent
    currentConversationId = conversationId
    peerIsTyping = false
    typingClearTask?.cancel()
    olderCursor = nil
    hasMoreOlder = false
    defer {isLoading = false}
    do{
      let page = try await getAllMessageUsecase.execute(conversationId: conversationId, cursor: nil, limit: pageLimit)
      // The view inverts the list, so keep the API order: most recent first.
      messages = page.items
      olderCursor = page.nextCursor
      hasMoreOlder = page.hasMore
    } catch {
      self.errorLoadMessages = error
      print(error)
    }
  }

  /// Loads older messages when scrolling up. The list is most-recent-first, so
  /// older ones are appended at the end and nothing shifts visually. No-op once
  /// there is no history left.
  func loadOlderMessages() async {
    guard let conversationId = currentConversationId,
          let cursor = olderCursor,
          !isLoadingOlder else { return }
    isLoadingOlder = true
    defer { isLoadingOlder = false }
    do {
      let page = try await getAllMessageUsecase.execute(conversationId: conversationId, cursor: cursor, limit: pageLimit)
      messages.append(contentsOf: page.items)
      olderCursor = page.nextCursor
      hasMoreOlder = page.hasMore
    } catch {
      self.errorLoadMessages = error
      print(error)
    }
  }
  
  /// Best effort: the customer has seen the conversation, so mark the studio's
  /// messages read. Errors are swallowed rather than disturbing the UI.
  func markRead(conversationId: String) async {
    // Nothing to mark when no studio message is unread, so skip the call.
    guard messages.contains(where: { $0.authorType.isStudio && $0.readAt == nil })
    else { return }
    do {
      try await markMessagesReadUsecase.execute(conversationId: conversationId)
    } catch {
      print("markRead failed: \(error)")
    }
  }

  /// Silent realtime refetch. Does not clear the list, so there is no flash.
  /// Merges the fresh first page with the history already loaded, and drops
  /// messages that vanished from the recent window, such as deletions.
  func refreshSilently() async {
    guard let conversationId = currentConversationId else { return }
    do {
      let page = try await getAllMessageUsecase.execute(
        conversationId: conversationId,
        cursor: nil,
        limit: pageLimit
      )
      if !page.hasMore {
        messages = page.items
        olderCursor = nil
        hasMoreOlder = false
      } else if let oldestFresh = page.items.last {
        let freshIds = Set(page.items.map(\.id))
        let olderKept = messages.filter { msg in
          !freshIds.contains(msg.id) && msg.createdAt < oldestFresh.createdAt
        }
        messages = page.items + olderKept
        olderCursor = page.nextCursor
        hasMoreOlder = true
      } else {
        messages = []
        olderCursor = nil
        hasMoreOlder = false
      }
      await markRead(conversationId: conversationId)
    } catch {
      print("refreshSilently failed: \(error)")
    }
  }

  /// Replaces a local message with its server version, on a realtime update.
  func upsertLocalMessage(_ message: Message) {
    if let index = messages.firstIndex(where: { $0.id == message.id }) {
      messages[index] = message
    }
  }

  /// Immediate local removal, on a realtime `support.message.deleted`.
  func removeLocalMessage(id: String) {
    messages.removeAll { $0.id == id }
  }

  func sendMessage(conversationId:String, body:String, attachments: [AttachmentInput] = []) async throws{
    do{
       let sendMessage = try await sendMessageUsecase.execute(conversationId: conversationId, body: body, attachments: attachments)
      // The new message is the most recent, so index 0 - visually the bottom.
      messages.insert(sendMessage, at: 0)
    } catch {
      // Cancellation (app backgrounded, screen closed) is not a real failure.
      if error.isAppwinCancelled { return }
      self.errorSendMessage = error
      print(error)
    }
  }

  /// Edits one of the customer's own messages, replacing the local version with
  /// the server's. Throwing keeps the view in edit mode.
  func updateMessage(conversationId: String, messageId: String, body: String) async throws {
    let updated = try await updateMessageUsecase.execute(conversationId: conversationId, messageId: messageId, body: body)
    if let index = messages.firstIndex(where: { $0.id == messageId }) {
      messages[index] = updated
    }
  }

  /// Deletes one of the customer's own messages, once the server confirms.
  func deleteMessage(conversationId: String, messageId: String) async {
    do {
      try await deleteMessageUsecase.execute(conversationId: conversationId, messageId: messageId)
      messages.removeAll { $0.id == messageId }
    } catch {
      self.errorSendMessage = error
      print(error)
    }
  }

  /// Toggles an emoji reaction, optimistically then synced.
  func toggleReaction(messageId: String, emoji: String) async {
    guard let conversationId = currentConversationId,
          let index = messages.firstIndex(where: { $0.id == messageId }) else { return }
    let previous = messages[index]
    messages[index] = Self.optimisticToggle(previous, emoji: emoji)
    do {
      let updated = try await toggleReactionUsecase.execute(
        conversationId: conversationId,
        messageId: messageId,
        emoji: emoji
      )
      if let i = messages.firstIndex(where: { $0.id == messageId }) {
        messages[i] = updated
      }
    } catch {
      if let i = messages.firstIndex(where: { $0.id == messageId }) {
        messages[i] = previous
      }
      print("toggleReaction failed: \(error)")
    }
  }

  private static func optimisticToggle(_ message: Message, emoji: String) -> Message {
    var reactions = message.reactions
    if let i = reactions.firstIndex(where: { $0.emoji == emoji }) {
      let current = reactions[i]
      if current.reactedByMe {
        let nextCount = current.count - 1
        if nextCount <= 0 {
          reactions.remove(at: i)
        } else {
          reactions[i] = MessageReaction(emoji: emoji, count: nextCount, reactedByMe: false)
        }
      } else {
        reactions[i] = MessageReaction(emoji: emoji, count: current.count + 1, reactedByMe: true)
      }
    } else {
      reactions.append(MessageReaction(emoji: emoji, count: 1, reactedByMe: true))
    }
    reactions.sort { lhs, rhs in
      if lhs.count != rhs.count { return lhs.count > rhs.count }
      return lhs.emoji < rhs.emoji
    }
    return Message(
      id: message.id,
      authorType: message.authorType,
      authorName: message.authorName,
      body: message.body,
      readAt: message.readAt,
      createdAt: message.createdAt,
      attachments: message.attachments,
      reactions: reactions
    )
  }

}
