//
//  File.swift
//  AppwinSupport
//
//  Created by Eliott on 05/06/2026.
//

import Foundation
import AppwinCore


final class ApiMessageRepository: MessageRepository {
  private let clientApi: ClientApi
  
  init(clientApi: ClientApi) {
    self.clientApi = clientApi
  }
  
  func send(conversationId: String, body: String, attachments: [AttachmentInput]) async throws -> Message {
    let dto: MessageDTO = try await clientApi.request(
      path: "/api/sdk/support/v1/conversations/\(conversationId)/messages",
      httpMethod: HttpMethod.post,
      body: SendMessageBody(
        body: body,
        attachments: attachments.map {
          SendMessageBody.AttachmentRef(
            storageKey: $0.storageKey,
            mimeType: $0.mimeType,
            sizeBytes: $0.sizeBytes,
            filename: $0.filename
          )
        }
      )
    )
    return try dto.toDomain()
  }
  
  func update(conversationId: String, messageId: String, body: String) async throws -> Message {
    let dto: MessageDTO = try await clientApi.request(
      path: "/api/sdk/support/v1/conversations/\(conversationId)/messages/\(messageId)",
      httpMethod: HttpMethod.patch,
      body: UpdateMessageBody(body: body)
    )
    return try dto.toDomain()
  }

  func delete(conversationId: String, messageId: String) async throws {
    try await clientApi.requestVoid(
      path: "/api/sdk/support/v1/conversations/\(conversationId)/messages/\(messageId)",
      httpMethod: HttpMethod.delete
    )
  }

  func getAll(conversationId: String, cursor: String?, limit: Int) async throws -> CursorPaginated<Message> {
    let query = CursorPageQuery(cursor: cursor, limit: limit)
    let page: CursorPage<MessageDTO> = try await clientApi.request(
      path: "/api/sdk/support/v1/conversations/\(conversationId)/messages\(query.queryString)",
      httpMethod: HttpMethod.get
    )
    return CursorPaginated(
      items: try page.data.map { try $0.toDomain() },
      nextCursor: page.nextCursor
    )
  }

  func markRead(conversationId: String) async throws {
    try await clientApi.requestVoid(path: "/api/sdk/support/v1/conversations/\(conversationId)/messages/read", httpMethod: HttpMethod.post)
  }

  func freshAttachmentURL(attachmentId: String) async throws -> URL {
    let dto: AttachmentUrlResponse = try await clientApi.request(
      path: "/api/sdk/support/v1/attachments/\(attachmentId)/url",
      httpMethod: HttpMethod.get
    )
    guard let url = URL(string: dto.url) else { throw AppwinApiError.invalidUrl }
    return url
  }

  func toggleReaction(conversationId: String, messageId: String, emoji: String) async throws -> Message {
    let dto: MessageDTO = try await clientApi.request(
      path: "/api/sdk/support/v1/conversations/\(conversationId)/messages/\(messageId)/reactions",
      httpMethod: HttpMethod.post,
      body: ToggleReactionBody(emoji: emoji)
    )
    return try dto.toDomain()
  }

  /// `GET .../attachments/:id/url` response, mirroring `AttachmentUrlSchema`.
  private struct AttachmentUrlResponse: Decodable {
    let url: String
  }

  private struct ToggleReactionBody: Encodable {
    let emoji: String
  }

  // Le serveur attend { body, attachments: [{ storageKey, mimeType, sizeBytes, filename }] }
  // (cf. ADR-0022 - flow upload via /sdk/v1/storage/sign-upload, le client
  // has already uploaded to S3 and the server inserts straight into
  // support_attachments, with no intermediate uploads lookup.
  private struct SendMessageBody: Encodable {
    let body: String
    let attachments: [AttachmentRef]
    struct AttachmentRef: Encodable {
      let storageKey: String
      let mimeType: String
      let sizeBytes: Int
      let filename: String
    }
  }

  // PATCH .../messages/:id expects { body }, mirroring UpdateMessageSchema.
  private struct UpdateMessageBody: Encodable {
    let body: String
  }
}
