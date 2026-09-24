//
//  File.swift
//  AppwinSupport
//
//  Created by Eliott on 04/06/2026.
//

import Foundation
import AppwinCore


final class ApiConversationRepository: ConversationRepository {
  private let clientApi: ClientApi
  
  init(clientApi: ClientApi) {
    self.clientApi = clientApi
  }
  
  func create(firstMessage: String, attachments: [AttachmentInput]) async throws -> Conversation {
    let dto: ConversationDTO = try await clientApi.request(
      path: "/api/sdk/support/v1/conversations",
      httpMethod: HttpMethod.post,
      body: CreateConversationBody(
        firstMessage: .init(
          body: firstMessage,
          attachments: attachments.map {
            CreateConversationBody.FirstMessage.AttachmentRef(
              storageKey: $0.storageKey,
              mimeType: $0.mimeType,
              sizeBytes: $0.sizeBytes,
              filename: $0.filename
            )
          }
        )
      )
    )
    Task { @MainActor in SupportInAppWatcher.noteConversationsExist() }
    return try dto.toDomain()
  }

  func getAll(cursor: String?, limit: Int) async throws -> CursorPaginated<Conversation> {
    let query = CursorPageQuery(cursor: cursor, limit: limit)
    let page: CursorPage<ConversationDTO> = try await clientApi.request(
      path: "/api/sdk/support/v1/conversations\(query.queryString)",
      httpMethod: HttpMethod.get
    )
    if !page.data.isEmpty {
      Task { @MainActor in SupportInAppWatcher.noteConversationsExist() }
    }
    return CursorPaginated(
      items: try page.data.map { try $0.toDomain() },
      nextCursor: page.nextCursor
    )
  }
  
  func get(id: String) async throws -> Conversation {
    let dto: ConversationDTO = try await clientApi.request(path: "/api/sdk/support/v1/conversations/\(id)", httpMethod: HttpMethod.get)
    return try dto.toDomain()
  }
  
  private struct CreateConversationBody: Encodable {
        struct FirstMessage: Encodable {
            let body: String
            let attachments: [AttachmentRef]
            struct AttachmentRef: Encodable {
                let storageKey: String
                let mimeType: String
                let sizeBytes: Int
                let filename: String
            }
        }
        let firstMessage: FirstMessage
    }

}


