//
//  File.swift
//  AppwinSupport
//
//  Created by Eliott on 04/06/2026.
//

import Foundation

final class CreateConversationUseCase: Sendable {
  
  private let repo: ConversationRepository
  
  
  init(repo: ConversationRepository) {
    self.repo = repo
  }
  
  func execute(firstMessage: String, attachments: [AttachmentInput]) async throws -> Conversation {
    try await repo.create(firstMessage: firstMessage, attachments: attachments)
  }
}
