//
//  RefreshAttachmentURLUseCase.swift
//  AppwinSupport
//
//  Re-signs a fresh signed GET URL for an attachment at the moment it is
//  opened. URLs returned when the conversation loaded expire after 15 minutes,
//  so a long-open conversation would fail on tap.
//

import Foundation

final class RefreshAttachmentURLUseCase: Sendable {
  private let repo: MessageRepository

  init(repo: MessageRepository) {
    self.repo = repo
  }

  func execute(attachmentId: String) async throws -> URL {
    try await repo.freshAttachmentURL(attachmentId: attachmentId)
  }
}
