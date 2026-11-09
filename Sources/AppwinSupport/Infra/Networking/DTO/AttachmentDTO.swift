// Raw network mirror of `AttachmentSchema` (packages/contracts): `url` is a
// temporary signed GET URL as a string, `createdAt` an ISO string.
// `toDomain()` converts it to the `Attachment` entity.

import Foundation

struct AttachmentDTO: Codable {
    let id: String
    let messageId: String
    let filename: String
    let mimeType: String
    let sizeBytes: Int
    let url: String
    let createdAt: String
}

extension AttachmentDTO {
    /// Network to domain. `messageId` is dropped, since the attachment already
    /// lives under its Message. The `url` string becomes a typed `URL`.
    func toDomain() throws -> Attachment {
        guard let parsedUrl = URL(string: url) else {
            throw DTOMappingError.unknownValue(field: "url", value: url)
        }
        return Attachment(
            id: id,
            filename: filename,
            mimeType: mimeType,
            sizeBytes: sizeBytes,
            url: parsedUrl,
            createdAt: try ISODate.requiredDate(createdAt, field: "createdAt")
        )
    }
}
