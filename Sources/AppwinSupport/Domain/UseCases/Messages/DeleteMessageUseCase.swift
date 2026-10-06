//
//  DeleteMessageUseCase.swift
//  AppwinSupport
//
//  Deletes one of the customer's messages. The server enforces that only the
//  (customer) peut supprimer SON message.
//

import Foundation

final class DeleteMessageUseCase: Sendable {
  private let repo: MessageRepository

  init(repo: MessageRepository) {
    self.repo = repo
  }

  func execute(conversationId: String, messageId: String) async throws {
    try await repo.delete(conversationId: conversationId, messageId: messageId)
  }
}
