// UploadOrchestrator - high-level facade for SDK uploads (ADR-0022).
//
// Optional compression, then sign-upload, then a multipart POST to S3, and it
// returns a storageKey the product passes to its own attach endpoint.

import Foundation

/// A successful upload. The caller hands `storageKey` to the product when
/// attaching (creating a message, a post, …).
public struct UploadedMediaRef: Sendable {
  public let storageKey: String
  public let mimeType: String
  public let sizeBytes: Int
  public let filename: String
}

/// Raw `POST /sdk/v1/storage/sign-upload` response.
private struct SignUploadResponse: Decodable {
  let storageKey: String
  let postUrl: String
  let fields: [String: String]
  let expiresInSec: Int
}

/// Body sent to `/sdk/v1/storage/sign-upload`.
private struct SignUploadBody: Encodable {
  let mimeType: String
  let sizeBytes: Int
}

/// `GET /sdk/v1/storage/sign-read` response.
private struct SignReadResponse: Decodable {
  let url: String
  let expiresAt: String
}

extension AppwinCore {
  /// Uploads a media file to S3 through the stateless Core endpoints
  /// (ADR-0022): optional image compression, sign-upload, multipart POST, then
  /// an `UploadedMediaRef` to hand to the product at attach time.
  ///
  /// Pass `compression: nil` to skip the compression step.
  ///
  /// - Throws: `AppwinApiError` on network or S3 failure.
  @MainActor
  public static func uploadMedia(
    data: Data,
    mimeType: String,
    filename: String,
    compression: MediaCompressionOptions? = .default,
    onProgress: @escaping @Sendable (Double) -> Void = { _ in }
  ) async throws -> UploadedMediaRef {
    guard let client = self.client else {
      throw AppwinApiError.invalidUrl // stands in for "configure was not called"
    }

    // sign-upload requires a bearer. `configure()` starts the bootstrap in the
    // background, but an app calling uploadMedia straight away hits a 100-500ms
    // window where it has not landed. Forcing it here is idempotent
    // server-side and a no-op once a token exists.
    if AuthSession.currentToken() == nil {
      _ = try await Self.bootstrapSession()
    }

    // Non-images and `compression: nil` pass through untouched.
    let (effectiveData, effectiveMime) = try await compressIfApplicable(
      data: data,
      mimeType: mimeType,
      options: compression
    )

    let signed: SignUploadResponse = try await client.request(
      path: "/api/sdk/v1/storage/sign-upload",
      httpMethod: .post,
      body: SignUploadBody(
        mimeType: effectiveMime,
        sizeBytes: effectiveData.count
      )
    )

    try await BucketUploader.upload(
      data: effectiveData,
      mimeType: effectiveMime,
      filename: filename,
      postUrl: signed.postUrl,
      fields: signed.fields,
      onProgress: onProgress
    )

    return UploadedMediaRef(
      storageKey: signed.storageKey,
      mimeType: effectiveMime,
      sizeBytes: effectiveData.count,
      filename: filename
    )
  }

  /// Trades a `(storageKey, customerId)` pair for a fresh signed S3 URL, valid
  /// 15 minutes. The `customerId` must match the current bearer or the server
  /// answers 403. Products showing private media call this again whenever the
  /// previous URL expires.
  @MainActor
  public static func signMediaURL(
    storageKey: String,
    customerId: String
  ) async throws -> URL {
    guard let client = self.client else {
      throw AppwinApiError.invalidUrl
    }
    // Same as uploadMedia: make sure a bearer exists before leaving.
    if AuthSession.currentToken() == nil {
      _ = try await Self.bootstrapSession()
    }
    let escapedKey = storageKey.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? storageKey
    let escapedCust = customerId.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? customerId
    let response: SignReadResponse = try await client.request(
      path: "/api/sdk/v1/storage/sign-read?storageKey=\(escapedKey)&customerId=\(escapedCust)",
      httpMethod: .get
    )
    guard let url = URL(string: response.url) else {
      throw AppwinApiError.invalidUrl
    }
    return url
  }

  /// Compresses when it applies (an image, and options supplied), else
  /// passes the bytes through.
  @MainActor
  private static func compressIfApplicable(
    data: Data,
    mimeType: String,
    options: MediaCompressionOptions?
  ) async throws -> (data: Data, mimeType: String) {
    guard let options = options, ImageCompressor.isImageMime(mimeType) else {
      return (data, mimeType)
    }
    return try await ImageCompressor.compress(
      data: data,
      inputMimeType: mimeType,
      options: options
    )
  }
}
