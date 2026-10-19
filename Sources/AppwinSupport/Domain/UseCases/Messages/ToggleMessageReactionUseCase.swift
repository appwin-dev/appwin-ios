//
//  ToggleMessageReactionUseCase.swift
//  AppwinSupport
//
//  Toggles an emoji reaction on a message, adding or removing it.
//

import Foundation

final class ToggleMessageReactionUseCase: Sendable {
  private let repo: MessageRepository

  init(repo: MessageRepository) {
    self.repo = repo
  }

  func execute(conversationId: String, messageId: String, emoji: String) async throws -> Message {
    try await repo.toggleReaction(
      conversationId: conversationId,
      messageId: messageId,
      emoji: emoji
    )
  }
}
