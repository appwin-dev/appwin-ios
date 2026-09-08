import Foundation

/// HTTP client shared by every Appwin product SDK.
///
/// Headers come from a closure rather than a fixed dictionary so `AppwinCore`
/// can change the identity - adding an `externalId` after `identify(...)` -
/// without repositories having to rebuild a client.
public final class ClientApi: Sendable {
  let baseUrl: String
  let headersProvider: @Sendable () -> [String: String]
  /// Transport seam: tests inject a stub instead of the shared URLSession.
  let dataFor: @Sendable (URLRequest) async throws -> (Data, URLResponse)

  /// Headers are resolved per request through the closure.
  public init(
    baseUrl: String,
    headersProvider: @escaping @Sendable () -> [String: String],
    dataFor: @escaping @Sendable (URLRequest) async throws -> (Data, URLResponse) = {
      try await URLSession.shared.data(for: $0)
    }
  ) {
    self.baseUrl = baseUrl
    self.headersProvider = headersProvider
    self.dataFor = dataFor
  }

  /// For previews and tests: headers captured once at init.
  public convenience init(baseUrl: String = "http://localhost", headers: [String: String]) {
    let captured = headers
    self.init(baseUrl: baseUrl, headersProvider: { captured })
  }

  /// `extraHeaders` supplements the identity headers for this request only,
  /// such as Community's `X-Appwin-Language`, which depends on the reader's
  /// locale and has no place among the canonical headers.
  public func request<T: Decodable>(
    path: String,
    httpMethod: HttpMethod,
    body: Encodable? = nil,
    extraHeaders: [String: String] = [:]
  ) async throws -> T {
    let request = try makeRequest(
      path: path,
      httpMethod: httpMethod,
      body: body,
      extraHeaders: extraHeaders
    )
    let data = try await send(request)
    do {
      return try JSONDecoder().decode(T.self, from: data)
    } catch {
      throw AppwinApiError.decodingFailed(error)
    }
  }

  /// For `204 No Content` endpoints.
  public func requestVoid(
    path: String,
    httpMethod: HttpMethod,
    body: Encodable? = nil,
    extraHeaders: [String: String] = [:]
  ) async throws {
    let request = try makeRequest(
      path: path,
      httpMethod: httpMethod,
      body: body,
      extraHeaders: extraHeaders
    )
    _ = try await send(request)
  }

  /// Exposes the status code and raw data without decoding, and without
  /// throwing on `304` - conditional ETag caching needs to see it.
  public func requestRaw(
    path: String,
    httpMethod: HttpMethod,
    extraHeaders: [String: String] = [:]
  ) async throws -> (status: Int, data: Data) {
    var request = try makeRequest(path: path, httpMethod: httpMethod, body: nil)
    for (key, value) in extraHeaders {
      request.setValue(value, forHTTPHeaderField: key)
    }
    // Bypass the URLSession cache: we want the server's real `304`, not a
    // locally reconstructed 200.
    request.cachePolicy = .reloadIgnoringLocalCacheData
    let data: Data
    let response: URLResponse
    do {
      (data, response) = try await dataFor(request)
    } catch {
      throw AppwinApiError.network(error)
    }
    guard let http = response as? HTTPURLResponse else {
      throw AppwinApiError.http(status: -1)
    }
    // `304` is a valid answer (cache is current), not an error.
    guard (200..<300).contains(http.statusCode) || http.statusCode == 304 else {
      throw AppwinApiError.http(status: http.statusCode)
    }
    return (http.statusCode, data)
  }

  // MARK: - Shared helpers

  private func makeRequest(
    path: String,
    httpMethod: HttpMethod,
    body: Encodable?,
    extraHeaders: [String: String] = [:]
  ) throws -> URLRequest {
    guard let url = URL(string: "\(baseUrl)\(path)") else { throw AppwinApiError.invalidUrl }
    var request = URLRequest(url: url)
    for (key, value) in headersProvider() {
      request.setValue(value, forHTTPHeaderField: key)
    }
    // Applied after the canonical ones, so a product can override a shared
    // header for one call.
    for (key, value) in extraHeaders {
      request.setValue(value, forHTTPHeaderField: key)
    }
    request.httpMethod = httpMethod.rawValue
    if let body {
      do {
        request.httpBody = try JSONEncoder().encode(body)
      } catch {
        throw AppwinApiError.encodingFailed(error)
      }
    }
    return request
  }

  /// POST with a pre-serialized JSON body, returning every HTTP status
  /// instead of throwing on non-2xx: the analytics sender maps each status
  /// to its own retry policy. Throws only when no response came back.
  func postRaw(path: String, body: Data) async throws -> (status: Int, data: Data) {
    guard let url = URL(string: "\(baseUrl)\(path)") else { throw AppwinApiError.invalidUrl }
    var request = URLRequest(url: url)
    for (key, value) in headersProvider() {
      request.setValue(value, forHTTPHeaderField: key)
    }
    request.httpMethod = HttpMethod.post.rawValue
    request.httpBody = body
    let data: Data
    let response: URLResponse
    do {
      (data, response) = try await dataFor(request)
    } catch {
      throw AppwinApiError.network(error)
    }
    guard let http = response as? HTTPURLResponse else {
      throw AppwinApiError.http(status: -1)
    }
    return (http.statusCode, data)
  }

  private func send(_ request: URLRequest) async throws -> Data {
    let data: Data
    let response: URLResponse
    do {
      (data, response) = try await dataFor(request)
    } catch {
      throw AppwinApiError.network(error)
    }
    guard let http = response as? HTTPURLResponse else {
      throw AppwinApiError.http(status: -1)
    }
    guard (200..<300).contains(http.statusCode) else {
      // The server returns a JSON body describing the refusal; print it,
      // because the status code alone rarely identifies which rule fired.
      print("API \(request.httpMethod ?? "?") \(request.url?.path ?? "?") failed (\(http.statusCode)):", String(decoding: data, as: UTF8.self))
      throw AppwinApiError.http(status: http.statusCode)
    }
    return data
  }
}
