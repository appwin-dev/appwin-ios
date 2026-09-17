import Foundation
import AppwinCore

/// Result of a confirmed community media upload (public URL for posts / avatars).
struct CommunityUploadedMedia: Equatable {
    let publicUrl: URL
    let mimeType: String
    let sizeBytes: Int
    let width: Int?
    let height: Int?
}

private struct CommunitySignUploadBody: Encodable {
    let mimeType: String
    let sizeBytes: Int
}

private struct CommunitySignUploadResponse: Decodable {
    let uploadId: String
    let storageKey: String
    let publicUrl: String
    let postUrl: String
    let fields: [String: String]
    let expiresInSec: Int
}

private struct CommunityConfirmUploadResponse: Decodable {
    let uploadId: String
    let storageKey: String
    let publicUrl: String
    let mimeType: String
    let sizeBytes: Int
    let fileName: String?
}

extension ApiCommunityRepository {
    /// Sign → S3 multipart → confirm. Returns a public URL for `createPost` / avatar.
    func uploadMedia(
        data: Data,
        mimeType: String,
        filename: String,
        width: Int?,
        height: Int?
    ) async throws -> CommunityUploadedMedia {
        let signed: CommunitySignUploadResponse = try await clientApi.request(
            path: "\(base)/uploads/sign",
            httpMethod: .post,
            body: CommunitySignUploadBody(mimeType: mimeType, sizeBytes: data.count)
        )

        try await BucketUploader.upload(
            data: data,
            mimeType: mimeType,
            filename: filename,
            postUrl: signed.postUrl,
            fields: signed.fields
        )

        let confirmed: CommunityConfirmUploadResponse = try await clientApi.request(
            path: "\(base)/uploads/\(signed.uploadId)/confirm",
            httpMethod: .post
        )

        guard let url = URL(string: confirmed.publicUrl) else {
            throw AppwinApiError.invalidUrl
        }

        return CommunityUploadedMedia(
            publicUrl: url,
            mimeType: confirmed.mimeType,
            sizeBytes: confirmed.sizeBytes,
            width: width,
            height: height
        )
    }
}
