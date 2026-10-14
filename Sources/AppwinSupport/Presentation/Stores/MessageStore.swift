
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

  /// Leaves the thread without wiping the list: the next `.task` reloads.
  ///
  /// Must clear `currentConversationId` so a realtime `refreshSilently` on
  /// home does not call markRead on a conversation the user is no longer
  /// viewing (that was clearing the unread pastille early).
  func leaveConversation() {
    currentConversationId = nil
    peerIsTyping = false
    typingClearTask?.cancel()
  }
  
  func loadMessages(conversationId: String) async throws {
    let pendingLocals = messages.filter { Self.isLocalId($0.id) }
    isLoading = true
    // Keep optimistic bubbles visible while the first page loads.
    if pendingLocals.isEmpty {
      messages = []
    }
    errorLoadMessages = nil
    currentConversationId = conversationId
    peerIsTyping = false
    typingClearTask?.cancel()
    olderCursor = nil
    hasMoreOlder = false
    defer { isLoading = false }
    do {
      let page = try await getAllMessageUsecase.execute(
        conversationId: conversationId,
        cursor: nil,
        limit: pageLimit
      )
      // The view inverts the list, so keep the API order: most recent first.
      messages = Self.mergingLocals(page.items, locals: pendingLocals)
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
    // Thread must still be on screen: a load started before pop must not clear
    // the unread pastille after the user left.
    guard conversationId == OpenThread.conversationId else { return }
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
        messages = Self.mergingLocals(page.items, locals: messages.filter { Self.isLocalId($0.id) })
        olderCursor = nil
        hasMoreOlder = false
      } else if let oldestFresh = page.items.last {
        let freshIds = Set(page.items.map(\.id))
        let locals = messages.filter { Self.isLocalId($0.id) }
        let olderKept = messages.filter { msg in
          !Self.isLocalId(msg.id) &&
            !freshIds.contains(msg.id) &&
            msg.createdAt < oldestFresh.createdAt
        }
        messages = Self.mergingLocals(page.items + olderKept, locals: locals)
        olderCursor = page.nextCursor
        hasMoreOlder = true
      } else {
        messages = messages.filter { Self.isLocalId($0.id) }
        olderCursor = nil
        hasMoreOlder = false
      }
      // Only while this thread is still on screen. A resync after the user
      // popped back to home must not clear the unread badge.
      guard conversationId == OpenThread.conversationId else { return }
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

  /// Inserts a customer bubble before the network round-trip (new conversation).
  @discardableResult
  func insertOptimisticCustomerMessage(body: String) -> String {
    let localId = Self.makeLocalId()
    messages.insert(Self.optimisticCustomerMessage(id: localId, body: body), at: 0)
    return localId
  }

  func sendMessage(conversationId: String, body: String, attachments: [AttachmentInput] = []) async throws {
    let localId = Self.makeLocalId()
    messages.insert(Self.optimisticCustomerMessage(id: localId, body: body), at: 0)

    do {
      let sent = try await sendMessageUsecase.execute(
        conversationId: conversationId,
        body: body,
        attachments: attachments
      )
      if let index = messages.firstIndex(where: { $0.id == localId }) {
        messages[index] = sent
      } else if messages.contains(where: { $0.id == sent.id }) {
        // Realtime already delivered the same message.
        messages.removeAll { $0.id == localId }
      } else {
        messages.insert(sent, at: 0)
      }
      // Detection runs after insert; refresh once language may be persisted.
      Task {
        try? await Task.sleep(nanoseconds: 2_500_000_000)
        try? await AppwinSupport.refreshCustomer()
      }
    } catch {
      messages.removeAll { $0.id == localId }
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
    Task {
      try? await Task.sleep(nanoseconds: 2_500_000_000)
      try? await AppwinSupport.refreshCustomer()
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
      translatedBody: message.translatedBody,
      readAt: message.readAt,
      createdAt: message.createdAt,
      attachments: message.attachments,
      reactions: reactions
    )
  }

  private static func makeLocalId() -> String { "local:\(UUID().uuidString)" }

  private static func isLocalId(_ id: String) -> Bool { id.hasPrefix("local:") }

  private static func optimisticCustomerMessage(id: String, body: String) -> Message {
    Message(
      id: id,
      authorType: .customer,
      authorName: nil,
      body: body,
      translatedBody: nil,
      readAt: nil,
      createdAt: Date(),
      // Attachments only exist after the server hydrates them.
      attachments: [],
      reactions: []
    )
  }

  /// Keeps optimistic bubbles until a matching server message replaces them.
  private static func mergingLocals(_ server: [Message], locals: [Message]) -> [Message] {
    guard !locals.isEmpty else { return server }
    var merged = server
    for local in locals.reversed() {
      let matched = server.contains {
        $0.authorType == .customer && $0.body == local.body && !isLocalId($0.id)
      }
      if !matched {
        merged.insert(local, at: 0)
      }
    }
    return merged
  }

}
