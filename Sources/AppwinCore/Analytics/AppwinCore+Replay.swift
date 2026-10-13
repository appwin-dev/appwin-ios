import Foundation

/// Replay settings served under `products.replay.config` (ADR-0057). Text
/// inputs are always masked, whatever these say.
@_spi(Appwin) public struct AppwinReplayConfig: Codable, Sendable, Equatable {
  public var sampleRate: Double
  public var maskAllText: Bool
  public var maskAllImages: Bool

  public init(sampleRate: Double = 1, maskAllText: Bool = true, maskAllImages: Bool = true) {
    self.sampleRate = min(max(sampleRate, 0), 1)
    self.maskAllText = maskAllText
    self.maskAllImages = maskAllImages
  }

  /// A missing field takes its default: the server may grow the config before
  /// every SDK in the wild knows the new keys.
  public init(from decoder: any Decoder) throws {
    let container = try decoder.container(keyedBy: CodingKeys.self)
    self.init(
      sampleRate: try container.decodeIfPresent(Double.self, forKey: .sampleRate) ?? 1,
      maskAllText: try container.decodeIfPresent(Bool.self, forKey: .maskAllText) ?? true,
      maskAllImages: try container.decodeIfPresent(Bool.self, forKey: .maskAllImages) ?? true)
  }
}

/// One part of a `multipart/form-data` body.
@_spi(Appwin) public struct AppwinMultipartPart: Sendable {
  public let name: String
  public let filename: String?
  public let contentType: String?
  public let data: Data

  public init(name: String, filename: String? = nil, contentType: String? = nil, data: Data) {
    self.name = name
    self.filename = filename
    self.contentType = contentType
    self.data = data
  }

  static func body(_ parts: [AppwinMultipartPart], boundary: String) -> Data {
    var body = Data()
    for part in parts {
      var disposition = "Content-Disposition: form-data; name=\"\(part.name)\""
      if let filename = part.filename { disposition += "; filename=\"\(filename)\"" }
      body.append(Data("--\(boundary)\r\n\(disposition)\r\n".utf8))
      if let contentType = part.contentType {
        body.append(Data("Content-Type: \(contentType)\r\n".utf8))
      }
      body.append(Data("\r\n".utf8))
      body.append(part.data)
      body.append(Data("\r\n".utf8))
    }
    body.append(Data("--\(boundary)--\r\n".utf8))
    return body
  }
}

// What the replay recorder of AppwinAnalytics needs from Core (ADR-0057). SPI
// rather than `package`: the Flutter and React Native bridges are pods of
// their own, outside the package name.
extension AppwinCore {
  /// The replay verdict, with the config when the product is open to this
  /// app. No config also under `unknown`: no verdict means no recording, but
  /// only `unavailable` is a definite no.
  @_spi(Appwin) public static func replayAvailability() async
    -> (result: AppwinInitResult, config: AppwinReplayConfig?)
  {
    let result = await availability(of: .replay)
    guard result.isReady else { return (result, nil) }
    let verdict = await _availability?.cachedVerdict()
    return (result, verdict?.products[AppwinProduct.replay.rawValue]?.config ?? AppwinReplayConfig())
  }

  /// The live analytics session, opened (or rotated after a timeout) first.
  /// Counts as activity: call it when the app comes to the foreground, not
  /// per frame. Nil before `AppwinAnalytics.initialize()` or under `.denied`.
  @_spi(Appwin) public nonisolated static func activeAnalyticsSessionId() async -> String? {
    guard let pipeline = analyticsPipeline else { return nil }
    return await pipeline.activeSessionId()
  }

  /// Authenticated multipart POST to an SDK route. Every HTTP status comes
  /// back as is; nil means no response (network, or not configured).
  @_spi(Appwin) public nonisolated static func postSdkMultipart(
    path: String, parts: [AppwinMultipartPart]
  ) async -> (status: Int, data: Data)? {
    guard let client = await MainActor.run(body: { AppwinCore.client }) else { return nil }
    let boundary = "Appwin-\(UUID().uuidString)"
    return try? await client.postRaw(
      path: path,
      body: AppwinMultipartPart.body(parts, boundary: boundary),
      contentType: "multipart/form-data; boundary=\(boundary)")
  }

  /// Mints a fresh bearer after a 401. False when it could not.
  @_spi(Appwin) public nonisolated static func reauthorizeSdkSession() async -> Bool {
    (try? await AppwinCore.bootstrapSession()) != nil
  }
}
