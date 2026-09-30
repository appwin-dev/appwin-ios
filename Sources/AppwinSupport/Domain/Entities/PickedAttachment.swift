// Media picked locally, ready to upload. First of the three concepts in the
// send flow: PickedAttachment (bytes) becomes AttachmentInput (reference after
// upload) becomes Attachment (returned by the server).
//
// It carries its real `mimeType` and `filename`: images are re-encoded to JPEG
// in the composer, videos and files are kept as they are.

import Foundation

struct PickedAttachment: Identifiable {
    let id = UUID()
    let data: Data
    let mimeType: String
    let filename: String
}
