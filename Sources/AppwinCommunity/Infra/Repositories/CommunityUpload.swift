import Foundation
import ImageIO
import UniformTypeIdentifiers
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

/// Upload-ready JPEG of a picked photo, with its final pixel size.
struct CommunityPreparedImage {
    let data: Data
    let width: Int
    let height: Int
}

/// Downsizes a picked photo before upload.
///
/// The camera original (a 12 MP HEIC can weigh 5-12 MB, and was sent labelled
/// `image/jpeg`) made the picker hang, then every feed reader downloaded it
/// again. Runs detached: `ImageCompressor` in Core is main-actor bound, and
/// decoding a large photo there froze the composer.
enum CommunityImagePrep {
    /// Post images are shown at screen width; 1600 px covers a 3x display.
    static let postMaxPixel: CGFloat = 1600

    static func prepare(_ data: Data, maxPixel: CGFloat = postMaxPixel) async -> CommunityPreparedImage? {
        await Task.detached(priority: .userInitiated) {
            guard let source = CGImageSourceCreateWithData(data as CFData, nil) else { return nil }
            let options: [CFString: Any] = [
                kCGImageSourceCreateThumbnailFromImageAlways: true,
                kCGImageSourceCreateThumbnailWithTransform: true,
                kCGImageSourceShouldCacheImmediately: true,
                kCGImageSourceThumbnailMaxPixelSize: maxPixel,
            ]
            guard let image = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary)
            else { return nil }
            let output = NSMutableData()
            guard let destination = CGImageDestinationCreateWithData(
                output as CFMutableData, UTType.jpeg.identifier as CFString, 1, nil
            ) else { return nil }
            CGImageDestinationAddImage(
                destination,
                image,
                [kCGImageDestinationLossyCompressionQuality: 0.8] as CFDictionary
            )
            guard CGImageDestinationFinalize(destination) else { return nil }
            return CommunityPreparedImage(data: output as Data, width: image.width, height: image.height)
        }.value
    }
}

extension CommunityRepository {
    /// Picked photo to public media: downsize, then sign / upload / confirm.
    func uploadImage(_ original: Data, filenamePrefix: String) async throws -> CommunityMedia {
        guard let prepared = await CommunityImagePrep.prepare(original) else {
            throw ImageCompressionError.decodingFailed
        }
        let uploaded = try await uploadMedia(
            data: prepared.data,
            mimeType: "image/jpeg",
            filename: "\(filenamePrefix)-\(UUID().uuidString).jpg",
            width: prepared.width,
            height: prepared.height
        )
        return CommunityMedia(
            url: uploaded.publicUrl,
            width: uploaded.width,
            height: uploaded.height,
            alt: nil,
            type: .image
        )
    }
}
