import Foundation

@MainActor
class FaqStore: ObservableObject {
  private let getAllFaqsUseCase: GetAllFaqsUseCase
  private let faqRepository: FaqRepository

  @Published private(set) var faqs: [Faq] = []
  @Published private(set) var categories: [FaqCategory] = []
  @Published private(set) var groups: [FaqGroup] = []
  @Published private(set) var isLoading = false

  init(getAllFaqsUseCase: GetAllFaqsUseCase, faqRepository: FaqRepository) {
    self.getAllFaqsUseCase = getAllFaqsUseCase
    self.faqRepository = faqRepository
  }

  /// Loads categories and published FAQs, grouped like the dashboard preview.
  func load() async {
    isLoading = true
    defer { isLoading = false }
    do {
      async let catsTask = faqRepository.getCategories()
      async let faqsTask = getAllFaqsUseCase.execute()
      let (cats, list) = try await (catsTask, faqsTask)
      categories = cats
      faqs = list
      groups = Self.buildGroups(categories: cats, faqs: list)
    } catch {
      print("FAQ load failed: \(error)")
    }
  }

  static func buildGroups(categories: [FaqCategory], faqs: [Faq]) -> [FaqGroup] {
    categories.compactMap { cat in
      let articles = faqs
        .filter { $0.categoryId == cat.id }
        .sorted { $0.position < $1.position }
      // Same rule as the preview: show the card even with no articles.
      return FaqGroup(category: cat, articles: articles)
    }
  }
}
