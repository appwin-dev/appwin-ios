import Foundation

final class GetAllFaqsUseCase: Sendable {
  private let repo: FaqRepository

  init(repo: FaqRepository) {
    self.repo = repo
  }

  func execute() async throws -> [Faq] {
    try await repo.getAll()
  }
}
