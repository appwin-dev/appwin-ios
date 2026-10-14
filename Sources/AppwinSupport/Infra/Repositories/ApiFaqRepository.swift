import Foundation
import AppwinCore

final class ApiFaqRepository: FaqRepository {
  private let clientApi: ClientApi

  init(clientApi: ClientApi) {
    self.clientApi = clientApi
  }

  func getAll() async throws -> [Faq] {
    let dtos: [FaqDTO] = try await clientApi.request(
      path: "/api/sdk/support/v1/faqs",
      httpMethod: HttpMethod.get
    )
    return dtos.map { $0.toDomain() }
  }

  func getCategories() async throws -> [FaqCategory] {
    let dtos: [FaqCategoryDTO] = try await clientApi.request(
      path: "/api/sdk/support/v1/faq-categories",
      httpMethod: HttpMethod.get
    )
    return dtos.map { $0.toDomain() }
  }
}
