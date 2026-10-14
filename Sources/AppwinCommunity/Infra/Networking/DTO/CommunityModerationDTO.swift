import Foundation

// In-app moderation DTOs, kept apart from the feed's: most members never load them.

struct ModerationQueueDTO: Decodable {
    let items: [ItemDTO]
    let pendingCount: Int
    let hasMore: Bool

    struct ItemDTO: Decodable {
        let targetType: String
        let targetId: String
        let contentStatus: String
        let aiCategories: [String]
        let reports: [ReportDTO]
        let post: CommunityPostDTO
        let comment: CommunityCommentDTO?

        /// `nil` for a target type this binary does not know.
        func toDomain() -> ModerationQueueItem? {
            guard let type = ModerationTargetType(rawValue: targetType) else { return nil }
            return ModerationQueueItem(
                targetType: type,
                targetId: targetId,
                status: ModerationContentStatus(rawValue: contentStatus) ?? .published,
                aiCategories: aiCategories,
                reports: reports.map { $0.toDomain() },
                post: post.toDomain(),
                comment: comment?.toDomain()
            )
        }
    }

    struct ReportDTO: Decodable {
        let id: String
        let reason: String
        let createdAt: String

        func toDomain() -> ModerationReport {
            ModerationReport(
                id: id,
                reason: reason,
                createdAt: CommunityDateParser.parse(createdAt) ?? Date()
            )
        }
    }

    func toDomain() -> ModerationQueuePage {
        ModerationQueuePage(
            items: items.compactMap { $0.toDomain() },
            pendingCount: pendingCount,
            hasMore: hasMore
        )
    }
}

struct ModerationDecisionBody: Encodable {
    let targetType: String
    let targetId: String
    let action: String
    let reason: String?
    let durationHours: Int?
    let reportIds: [String]
}

/// Only the fields set are sent: `nil` means « leave as is », `NSNull` clears a pin criterion.
struct ModeratePostBody: Encodable {
    var groupId: String?
    var isPinned: Bool?
    var pin: PinSettings?

    enum CodingKeys: String, CodingKey {
        case groupId, isPinned, pinnedUntil, pinMaxViewsPerMember
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encodeIfPresent(groupId, forKey: .groupId)
        try container.encodeIfPresent(isPinned, forKey: .isPinned)
        guard let pin else { return }
        if let until = pin.until {
            try container.encode(ISO8601DateFormatter().string(from: until), forKey: .pinnedUntil)
        } else {
            try container.encodeNil(forKey: .pinnedUntil)
        }
        if let views = pin.maxViewsPerMember {
            try container.encode(views, forKey: .pinMaxViewsPerMember)
        } else {
            try container.encodeNil(forKey: .pinMaxViewsPerMember)
        }
    }
}
