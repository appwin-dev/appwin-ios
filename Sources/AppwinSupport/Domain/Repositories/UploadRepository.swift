// Media upload access (ADR-0018, presigned flow).
//
// `upload` wraps the three network calls of an upload - sign, POST to the
// bucket, confirm - which is plumbing rather than domain logic, hence the Infra
// implementation.

import Foundation

protocol UploadRepository: Sendable {
    /// Uploads a media file and returns the reference to attach to a message.
    /// Signed against the customer, so no conversation needs to exist yet: the
    /// upload can precede the conversation's creation.
    func upload(
        data: Data,
        mimeType: String,
        filename: String,
        onProgress: @escaping @Sendable (Double) -> Void 
    ) async throws -> AttachmentInput
}
