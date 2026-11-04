import Foundation

// In-app moderation (Figma « Appwin InApp » 182:857 and its sheets): what
// moderators and admins see and decide, and the sanctions members are told about.

/// Where a reported or held content stands.
enum ModerationContentStatus: String, Equatable {
    case published, pending, removed, scheduled, draft
}

/// One content awaiting a decision, drawn as the feed draws it.
struct ModerationQueueItem: Identifiable, Equatable {
    var id: String { targetId }
    let targetType: ModerationTargetType
    let targetId: String
    let status: ModerationContentStatus
    /// What the classifier flagged (`support`, `spam`…), empty when it let the content through.
    let aiCategories: [String]
    let reports: [ModerationReport]
    /// The reported post, or the post the reported comment answers.
    let post: CommunityPost
    let comment: CommunityComment?
    /// The last decision on the content (« Traité par X »); `nil` while nothing was decided.
    let decision: ModerationDecisionInfo?

    /// Where the item stands once this moderator decided from the « Traités » tab.
    func decided(_ action: ModerationAction, by actorName: String) -> ModerationQueueItem {
        let newStatus: ModerationContentStatus
        switch action {
        case .restoreContent, .approve: newStatus = .published
        case .hideContent: newStatus = .pending
        case .removeContent: newStatus = .removed
        case .warn, .shadowBan, .ban: newStatus = status
        }
        return ModerationQueueItem(
            targetType: targetType,
            targetId: targetId,
            status: newStatus,
            aiCategories: aiCategories,
            reports: reports,
            post: post,
            comment: comment,
            decision: ModerationDecisionInfo(
                action: action.rawValue,
                actorName: actorName,
                automated: false,
                at: Date()
            )
        )
    }
}

/// Who decided last, and when (from the moderation log).
struct ModerationDecisionInfo: Equatable {
    /// Raw API action (`hide_content`…): older binaries may meet actions they do not know.
    let action: String
    /// A team member or an in-app moderator; `nil` for the classifier.
    let actorName: String?
    let automated: Bool
    let at: Date
}

/// The two tabs of the moderation screen, as on the dashboard.
enum ModerationQueueTab: String, CaseIterable, Equatable {
    case pending, resolved
}

enum ModerationTargetType: String, Equatable {
    case post, comment, profile
}

struct ModerationReport: Identifiable, Equatable {
    let id: String
    /// Raw key: older reports may carry reasons the app no longer offers.
    let reason: String
    let createdAt: Date
}

struct ModerationQueuePage: Equatable {
    let items: [ModerationQueueItem]
    let pendingCount: Int
    let hasMore: Bool
}

/// Decisions the app can take. Raw values are the API's.
enum ModerationAction: String, Equatable {
    case approve
    case hideContent = "hide_content"
    case removeContent = "remove_content"
    case restoreContent = "restore_content"
    case warn
    case shadowBan = "shadow_ban"
    case ban
}

/// Motifs offered when hiding or deleting (Figma 178:3480), sent as the decision's reason.
enum ModerationReason: String, CaseIterable, Equatable {
    case dissatisfaction
    case support
    case personalData = "personal_data"
    case duplicate
    case hateSpeech = "hate_speech"
    case sexualContent = "sexual_content"
    case violence
    case spam
    case selfHarm = "self_harm"
    case childSafety = "child_safety"
    case intellectualProperty = "intellectual_property"
    case impersonation
    case other
}

/// Ban and shadow ban lengths (Figma « Choisir la durée »).
enum SanctionDuration: CaseIterable, Equatable {
    case permanent, oneDay, sevenDays, thirtyDays

    var hours: Int? {
        switch self {
        case .permanent: return nil
        case .oneDay: return 24
        case .sevenDays: return 24 * 7
        case .thirtyDays: return 24 * 30
        }
    }
}

/// Pin settings of a post (Figma 178:3968): either criterion lifts the pin.
struct PinSettings: Equatable {
    var until: Date?
    var maxViewsPerMember: Int?
}
