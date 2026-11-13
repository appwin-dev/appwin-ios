import Foundation

final class GetAllConversationsUseCase: Sendable {
   private let repo: ConversationRepository
  
  init(repo: ConversationRepository) {
    self.repo = repo
  }

    func execute(cursor: String? = nil, limit: Int) async throws -> CursorPaginated<Conversation> {
      return try await repo.getAll(cursor: cursor, limit: limit)
    }
}
