//
//  UpdateMessageUseCase.swift
//  AppwinSupport
//
//  Edits the body of one of the customer's messages. The server enforces that
//  only the author can edit their own message.
//

import Foundation

final class UpdateMessageUseCase: Sendable {
  private let repo: MessageRepository

  init(repo: MessageRepository) {
    self.repo = repo
  }

  func execute(conversationId: String, messageId: String, body: String) async throws -> Message {
    try await repo.update(conversationId: conversationId, messageId: messageId, body: body)
  }
}
