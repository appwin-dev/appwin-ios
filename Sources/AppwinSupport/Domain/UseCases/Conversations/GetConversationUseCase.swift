//
//  File.swift
//  AppwinSupport
//
//  Created by Eliott on 04/06/2026.
//

import Foundation


final class GetConversationUseCase: Sendable {
  private let repo: ConversationRepository
  
  init(repo: ConversationRepository) {
    self.repo = repo
  }
  
  func execute(id: String) async throws -> Conversation {
    try await repo.get(id: id)
  }
  
  
}
