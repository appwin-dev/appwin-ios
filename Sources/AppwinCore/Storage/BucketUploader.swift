// BucketUploader - multipart upload to S3 from a presigned POST policy
// (ADR-0022). The API signs a policy and returns `fields`; the client POSTs
// straight to the bucket, which validates the signature server-side.
//
// It lives in Core because every product SDK needs it, and duplicating it would
// triple the chances of a multipart bug breaking one product's uploads.

import Foundation

public enum BucketUploader {
  /// Multipart POST of a file to an S3 bucket through a presigned POST policy.
  ///
  /// The caller already obtained `postUrl` and `fields` from the backend. This
  /// method only performs the direct transfer to the bucket.
  ///
  /// - Parameters:
  ///   - mimeType: must match the signed policy.
  ///   - filename: cosmetic on the S3 side.
  ///   - fields: policy fields, which must be sent **before** the file.
  ///   - onProgress: `0.0` to `1.0`, for a UI progress bar.
  ///
  /// - Throws: `AppwinApiError.http(status:)` when S3 rejects the upload
  ///           (expired signature, size over the limit, mime mismatch).
  public static func upload(
    data: Data,
    mimeType: String,
    filename: String,
    postUrl: String,
    fields: [String: String],
    onProgress: @escaping @Sendable (Double) -> Void = { _ in }
  ) async throws {
    guard let url = URL(string: postUrl) else { throw AppwinApiError.invalidUrl }
    let boundary = "Boundary-\(UUID().uuidString)"

    var request = URLRequest(url: url)
    request.httpMethod = HttpMethod.post.rawValue
    request.setValue(
      "multipart/form-data; boundary=\(boundary)",
      forHTTPHeaderField: "Content-Type"
    )
    let body = makeMultipartBody(
      boundary: boundary,
      fields: fields,
      fileData: data,
      mimeType: mimeType,
      filename: filename
    )

    let delegate = UploadProgressDelegate(onProgress: onProgress)
    let responseData: Data
    let response: URLResponse
    do {
      // `upload(for:from:delegate:)` rather than `data(for:)`: only this
      // overload surfaces progress events to the delegate. The body goes in
      // `from:`, not `request.httpBody`.
      (responseData, response) = try await URLSession.shared.upload(
        for: request,
        from: body,
        delegate: delegate
      )
    } catch {
      throw AppwinApiError.network(error)
    }
    guard let http = response as? HTTPURLResponse else {
      throw AppwinApiError.http(status: -1)
    }
    guard (200..<300).contains(http.statusCode) else {
      // S3 returns XML describing exactly why it refused; print it, because
      // the status code alone never says which of the three it was.
      print("S3 upload rejected (\(http.statusCode)):", String(decoding: responseData, as: UTF8.self))
      throw AppwinApiError.http(status: http.statusCode)
    }
  }

  /// multipart/form-data body: every presigned field first, then the file, in
  /// that order - S3 requires it. Strict CRLF throughout, or the bucket refuses
  /// the whole request.
  private static func makeMultipartBody(
    boundary: String,
    fields: [String: String],
    fileData: Data,
    mimeType: String,
    filename: String
  ) -> Data {
    var body = Data()
    let prefix = "--\(boundary)\r\n"

    // Policy fields (key, policy, signature, content-type, …).
    for (key, value) in fields {
      body.append(Data(prefix.utf8))
      body.append(Data("Content-Disposition: form-data; name=\"\(key)\"\r\n\r\n".utf8))
      body.append(Data("\(value)\r\n".utf8))
    }

    // The file, last.
    body.append(Data(prefix.utf8))
    body.append(Data("Content-Disposition: form-data; name=\"file\"; filename=\"\(filename)\"\r\n".utf8))
    body.append(Data("Content-Type: \(mimeType)\r\n\r\n".utf8))
    body.append(fileData)
    body.append(Data("\r\n".utf8))

    // Closing boundary; the trailing double dash ends the body.
    body.append(Data("--\(boundary)--\r\n".utf8))
    return body
  }
}

/// Forwards the share of bytes sent to `onProgress`. `Sendable` because
/// URLSession can call back from any thread.
private final class UploadProgressDelegate: NSObject, URLSessionTaskDelegate, Sendable {
  let onProgress: @Sendable (Double) -> Void

  init(onProgress: @escaping @Sendable (Double) -> Void) {
    self.onProgress = onProgress
  }

  func urlSession(
    _ session: URLSession,
    task: URLSessionTask,
    didSendBodyData bytesSent: Int64,
    totalBytesSent: Int64,
    totalBytesExpectedToSend: Int64
  ) {
    guard totalBytesExpectedToSend > 0 else { return }
    onProgress(Double(totalBytesSent) / Double(totalBytesExpectedToSend))
  }
}
