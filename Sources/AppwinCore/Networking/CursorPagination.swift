import Foundation

/// Query parameters for one page, cursor-paginated: what we **send**.
///
/// Swift mirror of the API's `CursorParams`. `cursor == nil` asks for the first
/// page. The cursor is **opaque**: the SDK never interprets it and hands it back
/// as-is, so each API domain stays free to change its keyset strategy without
/// touching this contract.
public struct CursorPageQuery: Sendable {
  public let cursor: String?
  public let limit: Int

  public init(cursor: String? = nil, limit: Int = 20) {
    self.cursor = cursor
    self.limit = limit
  }

  /// Ready to concatenate onto a path, e.g. `"?limit=20&cursor=abc"`.
  public var queryString: String {
    var items = [URLQueryItem(name: "limit", value: String(limit))]
    if let cursor {
      items.append(URLQueryItem(name: "cursor", value: cursor))
    }
    var components = URLComponents()
    components.queryItems = items
    guard let query = components.percentEncodedQuery, !query.isEmpty else { return "" }
    return "?\(query)"
  }
}

/// Generic cursor-paginated response: what we **receive**.
///
/// Swift mirror of the API's `CursorPage<T>`. Domain-agnostic: `T` comes from
/// the consumer.
///
/// - `nextCursor == nil` means there is no further page.
/// - `total` is only present on endpoints that can afford a `COUNT(*)`; it is
///   absent on the hot path.
public struct CursorPage<T: Decodable & Sendable>: Decodable, Sendable {
  public let data: [T]
  public let nextCursor: String?
  public let total: Int?

  public init(data: [T], nextCursor: String?, total: Int? = nil) {
    self.data = data
    self.nextCursor = nextCursor
    self.total = total
  }

  /// `true` while the server still exposes a next cursor.
  public var hasMore: Bool { nextCursor != nil }
}
