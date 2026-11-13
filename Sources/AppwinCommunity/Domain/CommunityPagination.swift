import Foundation

/// Shared page sizes for Community lists.
///
/// Keep in sync with Android `CommunityPagination` and the API
/// `CommunityFeedParamsSchema` default (20, max 50).
enum CommunityPagination {
    /// Feed / profile publications page size.
    static let feedPageSize = 20
    /// Root comments page size (offset pagination).
    static let commentsPageSize = 20
}
