//
//  File.swift
//  AppwinSupport
//
//  Created by Eliott on 05/06/2026.
//

import Foundation


final class GetAllMessagesUseCase: Sendable{
  private let repo: MessageRepository
  
  init(repo: MessageRepository) {
    self.repo = repo
  }
  
  func execute(conversationId: String, cursor: String? = nil, limit: Int) async throws -> CursorPaginated<Message> {
    return try await repo.getAll(conversationId: conversationId, cursor: cursor, limit: limit)
  }
  
}
