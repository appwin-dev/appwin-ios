//
//  File.swift
//  AppwinSupport
//
//  Created by Eliott on 23/06/2026.
//

import Foundation

final class StartConversationUseCase: Sendable {
  private let conversationRepository: ConversationRepository

  init(conversationRepository: ConversationRepository) {
    self.conversationRepository = conversationRepository
  }

  func execute(firstMessage: String, attachments: [AttachmentInput]) async throws -> Conversation {
    // The media are already uploaded, preloaded by the ComposerStore, so we get
    // the references directly. The create is atomic: text and attachments in one
    // message, one bubble, and no orphan conversation.
    try await conversationRepository.create(firstMessage: firstMessage, attachments: attachments)
  }
}
