
import Foundation

@MainActor
class ConversationStore: ObservableObject {
  private let  getAllConversationUseCase:GetAllConversationsUseCase
  private let  createConversationUseCase:CreateConversationUseCase
  private let  getconversationUsecase:GetConversationUseCase
  private let  startConversationUseCase:StartConversationUseCase
  @Published private(set) var conversations:[Conversation] = []
  @Published private(set) var conversation:Conversation?
  @Published private(set) var isLoading = false
  @Published private(set) var error: Error?
  /// Error specific to starting a conversation: create, upload and send.
  @Published private(set) var errorStart: Error?
  /// `true` while older conversations remain to load.
  @Published private(set) var hasMore = false
  /// `true` while loading a *following* page, unlike `isLoading` which covers
  /// the first full-screen load. Drives the small spinner at the list's foot.
  @Published private(set) var isLoadingMore = false
  /// Next-page cursor. `nil` means everything is loaded.
  private var nextCursor: String?
  /// Conversations loaded per fetch.
  private let pageLimit = 20


  init(getAllConversationUseCase: GetAllConversationsUseCase, createConversationUseCase: CreateConversationUseCase, getconversationUsecase: GetConversationUseCase, startConversationUseCase: StartConversationUseCase, conversations: [Conversation], conversation:Conversation?) {
    self.getAllConversationUseCase = getAllConversationUseCase
    self.createConversationUseCase = createConversationUseCase
    self.getconversationUsecase = getconversationUsecase
    self.startConversationUseCase = startConversationUseCase
    self.conversations = conversations
    self.conversation = conversation
    self.isLoading = isLoading
    self.error = error
  }
  
  func getAll() async {
    isLoading = true
    defer {isLoading = false}
    do {
      let page = try await getAllConversationUseCase.execute(cursor: nil, limit: pageLimit)
      conversations = page.items
      nextCursor = page.nextCursor
      hasMore = page.hasMore
    } catch {
      self.error = error
      print(error)
    }
  }

  /// Refetches the inbox without a full-screen spinner, on realtime events.
  func refreshSilently() async {
    do {
      let page = try await getAllConversationUseCase.execute(cursor: nil, limit: pageLimit)
      conversations = page.items
      nextCursor = page.nextCursor
      hasMore = page.hasMore
    } catch {
      print("conversation refreshSilently failed: \(error)")
    }
  }

  /// Loads the next inbox page. Sorted by recent activity, so older
  /// conversations are appended at the end. No-op once nothing is left.
  func loadMore() async {
    guard let cursor = nextCursor, !isLoadingMore else { return }
    isLoadingMore = true
    defer { isLoadingMore = false }
    do {
      let page = try await getAllConversationUseCase.execute(cursor: cursor, limit: pageLimit)
      conversations.append(contentsOf: page.items)
      nextCursor = page.nextCursor
      hasMore = page.hasMore
    } catch {
      self.error = error
      print(error)
    }
  }
  
  func create(firstMessage: String) async -> Conversation? {
    do {
    let conv = try await createConversationUseCase.execute(firstMessage: firstMessage, attachments: [])
      conversation = conv
      conversations.append(conv)
      return conv
    } catch {
      self.error = error
      print(error)
      return nil
    }
  }

  /// Starts a conversation with a first text message and any already-preloaded
  /// attachment references, through an atomic create.
  func start(firstMessage: String, attachments: [AttachmentInput]) async -> Conversation? {
    errorStart = nil
    do {
      let conv = try await startConversationUseCase.execute(firstMessage: firstMessage, attachments: attachments)
      conversation = conv
      conversations.append(conv)
      return conv
    } catch {
      // Cancellation (app backgrounded, screen closed) is not a real failure,
      // so show the user nothing.
      if error.isAppwinCancelled { return nil }
      // The upload is signed against the customer and the create is atomic, so
      // no orphan is possible: either everything lands or nothing is created.
      errorStart = error
      return nil
    }
  }
  
  func get(conversationId: String) async {
    isLoading = true
    defer {isLoading = false}
    do {
     conversation = try await getconversationUsecase.execute(id: conversationId)
    } catch {
      self.error = error
      print(error)
    }
  }
}
