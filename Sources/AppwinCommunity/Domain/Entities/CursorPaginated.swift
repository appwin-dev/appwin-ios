import Foundation

/// Cursor-paginated list, on the **domain** side.
///
/// Pure counterpart of `CursorPage<DTO>` (AppwinCore's `Decodable` network
/// envelope): Infra decodes `CursorPage<DTO>` then maps to this type over pure
/// domain entities. Named differently from `CursorPage` to avoid any collision
/// between the two modules.
///
/// Redefined here rather than shared from AppwinCore, as AppwinSupport already
/// does: the type is `internal` to each product, so the two copies never meet,
/// and Core stays confined to the network layer.
///
/// `nextCursor == nil` means there is nothing left to load.
struct CursorPaginated<Item: Sendable>: Sendable {
    let items: [Item]
    let nextCursor: String?

    var hasMore: Bool { nextCursor != nil }
}
