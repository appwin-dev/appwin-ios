import Foundation

/// Cursor-paginated list, on the **domain** side.
///
/// Pure counterpart of `CursorPage<DTO>` (AppwinCore's `Decodable` network
/// envelope): Infra decodes `CursorPage<DTO>` then maps to this type over
/// entities. Named differently on purpose, to avoid any collision between the
/// two modules.
///
/// `nextCursor == nil` means there is nothing left to load.
struct CursorPaginated<Item: Sendable>: Sendable {
  let items: [Item]
  let nextCursor: String?

  var hasMore: Bool { nextCursor != nil }
}
