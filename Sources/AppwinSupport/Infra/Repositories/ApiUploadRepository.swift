// Support-side adapter over `AppwinCore.uploadMedia` (ADR-0022).
//
// Core owns the whole flow: sign-upload, multipart POST to S3, and optional
// image compression. This repository only maps `UploadedMediaRef` to the
// Support domain's `AttachmentInput` and forwards the progress callback.

import Foundation
import AppwinCore

final class ApiUploadRepository: UploadRepository {
  func upload(
    data: Data,
    mimeType: String,
    filename: String,
    onProgress: @escaping @Sendable (Double) -> Void
  ) async throws -> AttachmentInput {
    // Fully delegated to Core. Compression is on by default for images
    // (ADR-0023) and passes through for PDFs and video. It can change the
    // effective mimeType, HEIC becoming JPEG.
    let ref = try await AppwinCore.uploadMedia(
      data: data,
      mimeType: mimeType,
      filename: filename,
      compression: .default,
      onProgress: onProgress
    )

    return AttachmentInput(
      storageKey: ref.storageKey,
      mimeType: ref.mimeType,
      sizeBytes: ref.sizeBytes,
      filename: ref.filename
    )
  }
}
