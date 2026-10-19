import Foundation

protocol FaqRepository: Sendable {
  /// Published FAQs of the current project, sorted by `position` server-side.
  func getAll() async throws -> [Faq]
  /// Categories of the current project.
  func getCategories() async throws -> [FaqCategory]
}
