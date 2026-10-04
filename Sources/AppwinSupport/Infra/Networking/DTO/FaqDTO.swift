import Foundation

struct FaqDTO: Decodable {
  let id: String
  let categoryId: String
  let question: String
  let answer: String
  let position: Int?
}

extension FaqDTO {
  func toDomain() -> Faq {
    Faq(
      id: id,
      categoryId: categoryId,
      question: question,
      answer: answer,
      position: position ?? 0
    )
  }
}

struct FaqCategoryDTO: Decodable {
  let id: String
  let name: String
}

extension FaqCategoryDTO {
  func toDomain() -> FaqCategory {
    FaqCategory(id: id, name: name)
  }
}
