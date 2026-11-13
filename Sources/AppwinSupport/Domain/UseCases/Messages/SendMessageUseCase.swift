//
//  File.swift
//  AppwinSupport
//
//  Created by Eliott on 05/06/2026.
//

import Foundation

final class SendMessageUseCase: Sendable {
  private let repo : MessageRepository
  
  
  init(repo: MessageRepository) {
    self.repo = repo
  }
  
  func execute(conversationId: String, body: String, attachments: [AttachmentInput]) async throws -> Message {
    try await repo.send(conversationId: conversationId, body: body, attachments: attachments)
  }
}
