// A message attachment as it comes **back** from the server, unlike the image
// picked locally, which is only `Data`. It is never built client-side: the
// server hydrates it on send and list, and we only decode and display it.
//
// `url` is a temporary signed GET URL on a private bucket, re-signed on every
// read, so it must not be persisted client-side.

import Foundation

struct Attachment: Identifiable, Equatable {
    let id: String
    let filename: String
    let mimeType: String
    let sizeBytes: Int
    let url: URL
    let createdAt: Date
}
