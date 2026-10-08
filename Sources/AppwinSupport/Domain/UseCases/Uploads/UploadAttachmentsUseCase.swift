// Uploads a list of media and returns their `AttachmentInput` references, ready
// to attach to a message.
//
// Shared by StartConversationUseCase (first message, which creates the
// conversation) and MessageStore.sendMessage. Each media carries its own
// mimeType and filename.

import Foundation

final class UploadAttachmentsUseCase: Sendable {
  private let uploadRepository: UploadRepository
  
  init(uploadRepository: UploadRepository) {
    self.uploadRepository = uploadRepository
  }
  
  func execute(media:PickedAttachment,onProgress: @escaping @Sendable (Double) -> Void) async throws -> AttachmentInput {
    return try await uploadRepository.upload(
      data: media.data, mimeType: media.mimeType, filename: media.filename, onProgress: onProgress,
    )
  }
}
