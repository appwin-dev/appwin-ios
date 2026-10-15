import Foundation

/// What an uploader does with a batch after one send attempt. Each case maps
/// to one branch of the retry policy - the uploaders never see HTTP. Shared
/// by every SDK upload (events, crashes, replay segments).
@_spi(Appwin) public enum SendOutcome: Sendable, Equatable {
  /// Server ingested the batch: delete the file.
  case ok
  /// Server dropped the batch by design (hard-capped plan): delete the file,
  /// do NOT retry, and cool down before the next attempt.
  case quotaExceeded
  /// Bearer refused: re-bootstrap the session once, then retry.
  case unauthorized
  /// 403: the product is switched off for this project. Events and crashes
  /// treat it as `fatal`; replay stops and purges.
  case forbidden
  /// Transient (network, 408, 429, 5xx): keep the file, back off.
  case retryable
  /// Deterministic refusal (400 and other 4xx): a bug, retrying would loop
  /// forever and block the queue behind it. Drop the file, log loudly.
  case fatal
}

protocol EventSender: Sendable {
  func send(lines: [String]) async -> SendOutcome
}

/// Real sender: wraps the wire lines in the ingest envelope and POSTs them.
struct ApiEventSender: EventSender {
  /// Resolved per send: the client does not exist before `configure()`.
  let client: @Sendable () -> ClientApi?

  private static let iso8601 = Date.ISO8601FormatStyle(includingFractionalSeconds: true)

  func send(lines: [String]) async -> SendOutcome {
    guard let client = client() else { return .retryable }
    // Lines are already wire-format JSON objects: the envelope is assembled
    // by joining them, never by re-parsing.
    let sentAt = Date().formatted(Self.iso8601)
    let body = Data("{\"events\":[\(lines.joined(separator: ","))],\"sentAt\":\"\(sentAt)\"}".utf8)
    let status: Int
    let data: Data
    do {
      (status, data) = try await client.postRaw(path: "/api/sdk/v1/events", body: body)
    } catch {
      return .retryable
    }
    let outcome = SendOutcome(status: status, data: data, label: "analytics batch")
    guard outcome == .ok else { return outcome }
    let response = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any]
    return (response?["quotaExceeded"] as? Bool) == true ? .quotaExceeded : .ok
  }
}

extension SendOutcome {
  /// The retry policy shared by every SDK ingest route. `status` nil means
  /// no response came back.
  public init(status: Int?, data: Data = Data(), label: String) {
    guard let status else {
      self = .retryable
      return
    }
    switch status {
    case 200..<300:
      self = .ok
    case 401:
      self = .unauthorized
    case 403:
      NSLog("[Appwin] %@ refused (403): %@", label, String(decoding: data, as: UTF8.self))
      self = .forbidden
    case 408, 429, 500...599:
      self = .retryable
    default:
      NSLog("[Appwin] %@ refused (%d): %@", label, status, String(decoding: data, as: UTF8.self))
      self = .fatal
    }
  }
}
