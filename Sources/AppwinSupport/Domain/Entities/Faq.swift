import Foundation

/// FAQ category, which groups articles on the SDK home screen.
struct FaqCategory: Identifiable, Hashable {
  let id: String
  let name: String
}

/// FAQ article: question, answer, category.
struct Faq: Identifiable, Hashable {
  let id: String
  let categoryId: String
  let question: String
  let answer: String
  let position: Int
}

/// A category with its articles, in dashboard order.
struct FaqGroup: Identifiable, Hashable {
  var id: String { category.id }
  let category: FaqCategory
  let articles: [Faq]
}
