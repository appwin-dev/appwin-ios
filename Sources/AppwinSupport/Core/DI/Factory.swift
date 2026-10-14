import Foundation
import AppwinCore
// Stores are created once, when the factory is called.
@MainActor
enum Factory {
  private static var client: ClientApi { AppwinCore.client! }
  
  static func makeMessageStore() -> MessageStore {
    let repo = ApiMessageRepository(clientApi: client)

    return MessageStore(
      getAllMessageUsecase: GetAllMessagesUseCase(repo: repo),
      sendMessageUsecase: SendMessageUseCase(repo: repo),
      markMessagesReadUsecase: MarkMessagesReadUseCase(repo: repo),
      refreshAttachmentURLUseCase: RefreshAttachmentURLUseCase(repo: repo),
      updateMessageUsecase: UpdateMessageUseCase(repo: repo),
      deleteMessageUsecase: DeleteMessageUseCase(repo: repo),
      toggleReactionUsecase: ToggleMessageReactionUseCase(repo: repo),
      messages: []
    )
  }
  
  static func makeConfigStore(appId: String) -> ConfigStore {
    ConfigStore(repo: ApiConfigRepository(clientApi: client), appId: appId)
  }

  static func makeComposerStore() -> ComposerStore {
    // ApiUploadRepository no longer takes clientApi: everything goes through
    // AppwinCore.uploadMedia (ADR-0022).
    let uploadRepo = ApiUploadRepository()
    return ComposerStore(uploadAttachmentsUseCase: UploadAttachmentsUseCase(uploadRepository: uploadRepo))
  }

  static func makeConversationStore() -> ConversationStore {
    let repo = ApiConversationRepository(clientApi: client)

    return ConversationStore(getAllConversationUseCase: GetAllConversationsUseCase(repo: repo),createConversationUseCase: CreateConversationUseCase(repo:repo),getconversationUsecase: GetConversationUseCase(repo:repo), startConversationUseCase: StartConversationUseCase(conversationRepository: repo), conversations: [], conversation: nil)
  }

  static func makeFaqStore() -> FaqStore {
    let repo = ApiFaqRepository(clientApi: client)
    return FaqStore(
      getAllFaqsUseCase: GetAllFaqsUseCase(repo: repo),
      faqRepository: repo
    )
  }
}
