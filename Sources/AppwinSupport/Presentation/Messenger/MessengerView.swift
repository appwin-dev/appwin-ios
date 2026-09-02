// Conversation screen, pushed onto the NavigationStack from Home.
//
// Two modes:
//  - `conversation` non-nil: an existing conversation, opened from the list;
//  - `conversation == nil`: a new one (Intercom model). The screen opens
//    empty and the first message sent creates it.
//
// The `MessageStore` is shared through @EnvironmentObject and repointed at the
// current conversation by `.task(id:)`.
// See docs/sdk-support-ios-state-management.md

import SwiftUI
import AppwinCore

struct MessengerView: View {
  @Environment(\.appwinTheme) private var theme
  @EnvironmentObject private var messageStore: MessageStore
  @EnvironmentObject private var conversationStore: ConversationStore
  @EnvironmentObject private var router: AppwinRouter
  @FocusState var isComposerFocused:Bool
  let conversation: Conversation?
  @State private var messageBody:String = ""
  @State private var composerFieldResetId = UUID()
  @State private var isSubmiting: Bool = false
  @EnvironmentObject private var composerStore: ComposerStore
  @EnvironmentObject private var configStore: ConfigStore
  @State private var createdConversation: Conversation?
  /// Message being edited via long press. `nil` means send mode, in which
  /// case the composer shows no banner and the button sends.
  @State private var editingMessage: Message?
  /// Last typing state emitted, to avoid spamming the socket.
  @State private var lastTypingSent = false
  @State private var typingStopTask: Task<Void, Never>?

  private var activeConversation: Conversation? {
    conversation ?? createdConversation        // param, sinon celle qu'on vient de créer
  }

  /// Welcome banner: a new conversation, or one created in this session.
  private var showsWelcomeBanner: Bool {
    guard configStore.config.messaging.welcomeMessageEnabled else { return false }
    let text = configStore.config.messaging.welcomeMessage
      .trimmingCharacters(in: .whitespacesAndNewlines)
    guard !text.isEmpty else { return false }
    return conversation == nil || createdConversation != nil
  }

  private func emitTyping(_ isTyping: Bool) {
    guard activeConversation?.id != nil else { return }
    if lastTypingSent == isTyping { return }
    lastTypingSent = isTyping
    AppwinSupport.emitTyping(conversationId: activeConversation?.id, isTyping: isTyping)
  }

  private func notifyDraftTyping(_ text: String) {
    let typing = !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    emitTyping(typing)
    typingStopTask?.cancel()
    if typing {
      typingStopTask = Task {
        try? await Task.sleep(nanoseconds: 2_000_000_000)
        guard !Task.isCancelled else { return }
        emitTyping(false)
      }
    }
  }

  /// Long-press Edit: lifts the message text back into the composer and
  /// switches to edit mode. Focusing opens the keyboard.
  private func beginEdit(_ message: Message) {
    editingMessage = message
    messageBody = message.body
    isComposerFocused = true
  }

  /// Cancels the edit: clears the composer and returns to send mode.
  private func cancelEdit() {
    editingMessage = nil
    messageBody = ""
    composerFieldResetId = UUID()
  }

  /// Long-press Delete. The store removes the bubble on success.
  private func deleteMessage(_ message: Message) {
    guard let id = activeConversation?.id else { return }
    // That message was the one being edited, so leave edit mode.
    if editingMessage?.id == message.id { cancelEdit() }
    Task { await messageStore.deleteMessage(conversationId: id, messageId: message.id) }
  }

  private func submitMessage() {
    // Edit mode commits the change to the target message rather than sending.
    if let editing = editingMessage { submitEdit(editing); return }

    if messageBody.isEmpty && composerStore.pendingUploads.isEmpty { return }
    // Real double-tap guard: `submitMessage` is synchronous, so the previous
    // `defer` reset the flag before the network call finished. Block re-entry
    // and only release the flag when the Task ends.
    if isSubmiting { return }
    isSubmiting = true

    // Capture and reset the composer at once, so the send runs on frozen values.
    let body = messageBody
    let refs = composerStore.readyUploads
    messageBody = ""
    composerFieldResetId = UUID()
    emitTyping(false)
    composerStore.clear()

    Task {
      defer { isSubmiting = false }
      guard let id = activeConversation?.id else {
        // No conversation yet: this first message creates it.
        if let conv = await conversationStore.start(firstMessage: body, attachments: refs) {
          createdConversation = conv
        }
        return
      }
      try? await messageStore.sendMessage(conversationId: id, body: body, attachments: refs)
    }
  }

  /// Commits an edit. Empty text is ignored, since the server requires a body
  /// of at least one character.
  private func submitEdit(_ message: Message) {
    let body = messageBody.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !body.isEmpty, let id = activeConversation?.id else { return }
    if isSubmiting { return }
    isSubmiting = true
    Task {
      defer { isSubmiting = false }
      do {
        try await messageStore.updateMessage(conversationId: id, messageId: message.id, body: body)
        editingMessage = nil
        messageBody = ""
        composerFieldResetId = UUID()
      } catch {
        // On failure, stay in edit mode so the user can retry.
        print(error)
      }
    }
  }
  var body: some View {
    content
    
    // Re-runs on every id change, reloading the open conversation's messages.
    // `nil` means a new conversation, so there is nothing to load.
      .task(id: activeConversation?.id) {
        guard let id = activeConversation?.id else {
          // New-conversation screen: no messages from a previous one.
          messageStore.resetForNewConversation()
          return
        }
        try? await messageStore.loadMessages(conversationId: id)
          // The customer has now seen the conversation, so mark the studio's
          // messages read. Best effort.
        await messageStore.markRead(conversationId: id)
      }
    // Leaving the screen clears the composer: it is shared, so without this the
    // draft would leak onto the next conversation.
      .onDisappear {
        typingStopTask?.cancel()
        emitTyping(false)
        composerStore.clear()
        cancelEdit()
      }
      .onChange(of: messageBody) { newValue in
        if editingMessage == nil {
          notifyDraftTyping(newValue)
        }
      }
  }
  
  /// Assembles the components: header on top, list in the middle, composer at
  /// the bottom. No navigation bar: home and the thread are one sheet panel,
  /// and they share the same `Header`, so the close button pops instead of
  /// dismissing.
  private var content: some View {
    VStack(spacing: 0) {
      Header(context: configStore.config.context, onClose: { router.pop() })
        .padding(.horizontal, 20)
        .padding(.top, 20)
        // The list adds 16 of its own, for the 24 gap home has under its header.
        .padding(.bottom, 8)

      MessageList(
        store: messageStore,
        showWelcome: showsWelcomeBanner,
        welcomeMessage: configStore.config.messaging.welcomeMessage,
        onBackgroundTap: { isComposerFocused = false },
        onEditMessage: beginEdit,
        onDeleteMessage: deleteMessage,
        onToggleReaction: { message, emoji in
          Task { await messageStore.toggleReaction(messageId: message.id, emoji: emoji) }
        }
      )
      // While editing, the rest of the conversation is dimmed to focus
      // attention on the message being changed.
      .grayscale(editingMessage != nil ? 1 : 0)
      .opacity(editingMessage != nil ? 0.4 : 1)
      .animation(.easeInOut(duration: 0.2), value: editingMessage != nil)
      if let erreur = messageStore.errorSendMessage ?? conversationStore.errorStart {
        Text(erreur.appwinUserMessage)
          .font(theme.fonts.caption)
          .foregroundColor(theme.colors.textSecondary)
          .padding(.horizontal)
      }
      MessengerComposer(
        text: $messageBody,
        fieldResetId: composerFieldResetId,
        isSubmitting: isSubmiting,
        isFocused: $isComposerFocused,
        isEditing: editingMessage != nil,
        onCancelEdit: cancelEdit,
        onSend: submitMessage
      )
    }
    .toolbar(.hidden, for: .navigationBar)
    .navigationBarBackButtonHidden(true)
    // Hiding the bar also kills the edge swipe, which this puts back.
    .enableInteractivePopGesture()
    .background(AppwinTokens.surfaceMuted.ignoresSafeArea())
  }
}

// MARK: - Preview
//
// No network in previews: a fake `MessageRepository` returns dummy messages, so
// `.task` succeeds and the bubbles render. The `MessageStore` is supplied via
// `.environmentObject`, without which @EnvironmentObject crashes. Do not go
// through `Factory` here.

private struct PreviewMessageRepository: MessageRepository {
  func getAll(conversationId: String, cursor: String?, limit: Int) async throws -> CursorPaginated<Message> {
    CursorPaginated(
      items: [
        Message(id: "1", authorType: .organizationMember, authorName: "Studio",
                body: "Bonjour 👋 comment puis-je vous aider ?", readAt: nil, createdAt: .now, attachments: [], reactions: []),
        Message(id: "2", authorType: .customer, authorName: nil,
                body: "Salut, j'ai une question sur ma commande", readAt: nil, createdAt: .now, attachments: [], reactions: []),
        Message(id: "3", authorType: .organizationMember, authorName: "Studio",
                body: "Bien sûr, donnez-moi votre numéro de commande", readAt: nil, createdAt: .now, attachments: [], reactions: []),
      ],
      nextCursor: nil
    )
  }
  func send(conversationId: String, body: String, attachments: [AttachmentInput]) async throws -> Message {
    Message(id: "x", authorType: .customer, authorName: nil, body: body, readAt: nil, createdAt: .now, attachments: [], reactions: [])
  }
  func update(conversationId: String, messageId: String, body: String) async throws -> Message {
    Message(id: messageId, authorType: .customer, authorName: nil, body: body, readAt: nil, createdAt: .now, attachments: [], reactions: [])
  }
  func delete(conversationId: String, messageId: String) async throws {}
  func markRead(conversationId: String) async throws {}
  func freshAttachmentURL(attachmentId: String) async throws -> URL {
    URL(string: "https://example.com/\(attachmentId)")!
  }
  func toggleReaction(conversationId: String, messageId: String, emoji: String) async throws -> Message {
    Message(id: messageId, authorType: .customer, authorName: nil, body: "", readAt: nil, createdAt: .now, attachments: [], reactions: [
      MessageReaction(emoji: emoji, count: 1, reactedByMe: true),
    ])
  }
}

#Preview {
  
  let repo = PreviewMessageRepository()
  let client = ClientApi(headers: [:])
  let store = MessageStore(
    getAllMessageUsecase: GetAllMessagesUseCase(repo: repo),
    sendMessageUsecase: SendMessageUseCase(repo: repo),
    markMessagesReadUsecase: MarkMessagesReadUseCase(repo: repo),
    refreshAttachmentURLUseCase: RefreshAttachmentURLUseCase(repo: repo),
    updateMessageUsecase: UpdateMessageUseCase(repo: repo),
    deleteMessageUsecase: DeleteMessageUseCase(repo: repo),
    toggleReactionUsecase: ToggleMessageReactionUseCase(repo: repo),
    messages: []
  )
  // conversationStore and router are @EnvironmentObject of MessengerView too,
  // so they must be supplied or the preview crashes at runtime.
  let conversationStore = ConversationStore(
    getAllConversationUseCase: GetAllConversationsUseCase(repo: ApiConversationRepository(clientApi: client)),
    createConversationUseCase: CreateConversationUseCase(repo: ApiConversationRepository(clientApi: client)),
    getconversationUsecase: GetConversationUseCase(repo: ApiConversationRepository(clientApi: client)),
    startConversationUseCase: StartConversationUseCase(conversationRepository: ApiConversationRepository(clientApi: client)),
    conversations: [], conversation: nil
  )
  let router = AppwinRouter()
  let conversation = Conversation(
    id: "preview", preview: "Ma conversation", status: .open,
    lastMessageAt: nil, lastReadAt: nil, createdAt: .now
  )

  NavigationStack {
    MessengerView(conversation: conversation)
      .environmentObject(store)
      .environmentObject(conversationStore)
      .environmentObject(router)
      .environmentObject(ComposerStore(uploadAttachmentsUseCase: UploadAttachmentsUseCase(uploadRepository: ApiUploadRepository())))
      .environmentObject(ConfigStore(repo: ApiConfigRepository(clientApi: client), appId: "preview"))
  }
}
