//
//  MarkMessagesReadUseCase.swift
//  AppwinSupport
//
//  The customer has seen the conversation, so mark the studio's messages read
//  by setting `readAt` server-side. Feeds the read receipt in the dashboard.
//

import Foundation


final class MarkMessagesReadUseCase: Sendable {
  private let repo: MessageRepository

  init(repo: MessageRepository) {
    self.repo = repo
  }

  func execute(conversationId: String) async throws {
    try await repo.markRead(conversationId: conversationId)
  }
}
