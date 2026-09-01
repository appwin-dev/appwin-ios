// Upload reference, attached to a message on `send`. Second of the three
// concepts in the send flow: PickedAttachment (bytes) becomes AttachmentInput
// (reference after upload) becomes Attachment (returned by the server).
//
// Under ADR-0022 the client uploaded straight to S3 and got an opaque
// `storageKey`; the denormalised metadata sent here is inserted directly into
// `support_attachments`, with no intermediate `uploads` lookup.

import Foundation

struct AttachmentInput: Codable, Sendable {
  let storageKey: String
  let mimeType: String
  let sizeBytes: Int
  let filename: String
}
