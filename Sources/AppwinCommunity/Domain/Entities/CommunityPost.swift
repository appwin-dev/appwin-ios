// Domain entity shaped by what the feed displays, not by the API.
//
// Types propres : `Date` (pas String ISO), `URL` (pas String), enums (pas
// The server's moderation fields (`moderationScore`, `reportCount`, …) do not
// surface here: the SDK does nothing with them, and carrying them would give
// them a chance of ending up on screen.

import Foundation

struct CommunityPost: Identifiable, Equatable {
    let id: String
    let groupId: String
    let groupName: String
    /// `nil` when the author was erased with no frozen name.
    let author: CommunityAuthor?
    let body: String
    /// Translation in the reader's language, `nil` when useless or unavailable.
    let translatedBody: String?
    let sourceLanguage: String?
    let media: [CommunityMedia]
    let poll: CommunityPoll?
    let isPinned: Bool
    /// Team badge on the post, independent of the author's role.
    let hasAdminTag: Bool
    let likeCount: Int
    let commentCount: Int
    let viewCount: Int
    /// The reader's reaction, `nil` when they have not reacted.
    let myReaction: CommunityReactionKind?
    /// Up to 3 most frequent reactions on the post (any reader), for the summary.
    let topReactions: [CommunityReactionKind]
    /// Full per-kind breakdown (sorted by volume), for the tap-to-detail sheet.
    let reactionCounts: [CommunityReactionCount]
    let canEdit: Bool
    let canDelete: Bool
    /// Visible to the author alone: held by moderation, or shadow banned.
    let isPendingReview: Bool
    let publishedAt: Date
    let editedAt: Date?
}

/// One reaction kind with its count on a post or comment.
struct CommunityReactionCount: Equatable, Identifiable {
    var id: CommunityReactionKind { kind }
    let kind: CommunityReactionKind
    let count: Int
}

/// Local preview of a reaction toggle before the server answers.
///
/// Must update `reactionCounts` and re-derive `topReactions`: filtering
/// `topReactions` alone empties the summary when the toggled kind was the only
/// entry, which flashed the UI fallback heart until the round trip landed.
struct OptimisticReactionState: Equatable {
    let myReaction: CommunityReactionKind?
    let topReactions: [CommunityReactionKind]
    let reactionCounts: [CommunityReactionCount]
    let likeCount: Int
}

func optimisticReactionState(
    myReaction: CommunityReactionKind?,
    reactionCounts: [CommunityReactionCount],
    likeCount: Int,
    kind: CommunityReactionKind
) -> OptimisticReactionState {
    let removing = myReaction == kind
    var counts: [CommunityReactionKind: Int] = [:]
    for entry in reactionCounts where entry.count > 0 {
        counts[entry.kind] = entry.count
    }
    if removing {
        let next = (counts[kind] ?? 1) - 1
        if next <= 0 {
            counts.removeValue(forKey: kind)
        } else {
            counts[kind] = next
        }
    } else if let previous = myReaction {
        let previousNext = (counts[previous] ?? 1) - 1
        if previousNext <= 0 {
            counts.removeValue(forKey: previous)
        } else {
            counts[previous] = previousNext
        }
        counts[kind] = (counts[kind] ?? 0) + 1
    } else {
        counts[kind] = (counts[kind] ?? 0) + 1
    }
    let nextCounts = counts
        .map { CommunityReactionCount(kind: $0.key, count: $0.value) }
        .sorted { $0.count > $1.count }
    let nextLike: Int
    if removing {
        nextLike = max(0, likeCount - 1)
    } else if myReaction != nil {
        nextLike = likeCount
    } else {
        nextLike = likeCount + 1
    }
    return OptimisticReactionState(
        myReaction: removing ? nil : kind,
        topReactions: Array(nextCounts.prefix(3).map(\.kind)),
        reactionCounts: nextCounts,
        likeCount: nextLike
    )
}

/// Author as displayed under a piece of content. The bare minimum: any extra
/// field is one more to invalidate when the profile changes.
struct CommunityAuthor: Equatable {
    let id: String
    let nickname: String
    let avatarUrl: URL?
    let role: CommunityMemberRole
    /// Team badge under the name, driven by the studio rather than the role.
    let isTeam: Bool

    /// False for the sentinel id used when a snapshot remains but no profile
    /// is addressable (erased member, legacy studio post without a profile).
    var isAddressable: Bool {
        id != Self.unaddressableId
    }

    static let unaddressableId = "00000000-0000-0000-0000-000000000000"
}

enum CommunityMemberRole: String, Equatable {
    case member, moderator, admin
}

struct CommunityPoll: Equatable {
    let options: [CommunityPollOption]
    let totalVotes: Int
    let myOptionId: String?
}

struct CommunityPollOption: Identifiable, Equatable {
    let id: String
    let text: String
    let voteCount: Int
}

enum CommunityMediaType: String, Equatable {
    case image, video
}

/// Media attached to a post. `width` and `height` let the space be reserved
/// before loading, so nothing jumps while scrolling.
struct CommunityMedia: Identifiable, Equatable {
    var id: String { url.absoluteString }
    let url: URL
    let width: Int?
    let height: Int?
    let alt: String?
    let type: CommunityMediaType

    var isVideo: Bool { type == .video }

    /// Width-to-height ratio, `nil` when the dimensions are missing.
    var aspectRatio: CGFloat? {
        guard let width, let height, height > 0 else { return nil }
        return CGFloat(width) / CGFloat(height)
    }

    /// Prefer the API `type` string; fall back to the URL extension for older
    /// payloads that predate the field.
    static func resolveType(apiType: String?, url: URL) -> CommunityMediaType {
        if let apiType, let parsed = CommunityMediaType(rawValue: apiType) {
            return parsed
        }
        switch url.pathExtension.lowercased() {
        case "mp4", "mov", "m4v":
            return .video
        default:
            return .image
        }
    }
}
