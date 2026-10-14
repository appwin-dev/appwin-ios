import Foundation

// Labels of the in-app moderation, reactions and report reasons.

extension CommunityStrings {
    static var reportSheetTitle: String { t("community.report_sheet_title", "Report") }
    static var reportQuestion: String { t("community.report_question", "Why do you want to report this content?") }
    static var validate: String { t("community.validate", "Confirm") }
    static func moderationTitle(_ count: Int) -> String {
        String(format: t("community.moderation_title", "Moderation (%d)"), count)
    }
    static var moderationInfo: String { t("community.moderation_info", "As a **moderator** you can decide to hide the posts members reported.") }
    static var moderationEmpty: String { t("community.moderation_empty", "Nothing to review") }
    static var moderationEmptyHint: String { t("community.moderation_empty_hint", "Reported posts show up here.") }
    static var restore: String { t("community.restore", "Restore") }
    static var leave: String { t("community.leave", "Leave") }
    static var hide: String { t("community.hide", "Hide") }
    static var confirmHide: String { t("community.confirm_hide", "Confirm hiding") }
    static var confirmRemove: String { t("community.confirm_remove", "Confirm deletion") }
    static var statusHidden: String { t("community.status_hidden", "Hidden") }
    static var statusRemoved: String { t("community.status_removed", "Deleted") }
    static func reportsCount(_ count: Int) -> String {
        String(format: t("community.reports_count", "%d reports"), count)
    }
    static func reportsCountOne(_ count: Int) -> String {
        String(format: t("community.reports_count_one", "%d report"), count)
    }
    static func reportsAutoHidden(_ count: Int) -> String {
        String(format: t("community.reports_auto_hidden", "Given the number of reports (%d), **the post was hidden automatically.**"), count)
    }
    static var moveToGroup: String { t("community.move_to_group", "Change group") }
    static var pinAction: String { t("community.pin_action", "Pin") }
    static var unpinAction: String { t("community.unpin_action", "Unpin") }
    static var chooseReason: String { t("community.choose_reason", "Choose a reason") }
    static func removeInfo(_ name: String) -> String {
        String(format: t("community.remove_info", "The post will be deleted, and **@%@** will be told about the sanction and its reason."), name)
    }
    static func hideInfo(_ name: String) -> String {
        String(format: t("community.hide_info", "**@%@** will still see their post, but the rest of the community won’t."), name)
    }
    static var chooseGroupTitle: String { t("community.choose_group_title", "Choose a group") }
    static var moveAction: String { t("community.move_action", "Move") }
    static var pinTitle: String { t("community.pin_title", "Pin settings") }
    static var pinInfo: String { t("community.pin_info", "The pin stops at the first criterion reached. Choose at least one.") }
    static var pinUntilTitle: String { t("community.pin_until_title", "An end date for the whole community") }
    static var pinUntilHint: String { t("community.pin_until_hint", "The post is unpinned for every member on that date.") }
    static var pinViewsTitle: String { t("community.pin_views_title", "Maximum views per member") }
    static var pinViewsHint: String { t("community.pin_views_hint", "Each member sees the pinned post at most N times") }
    static var pinTimes: String { t("community.pin_times", "times") }
    static var warnAction: String { t("community.warn_action", "Warn") }
    static var shadowBanAction: String { t("community.shadow_ban_action", "Shadow ban") }
    static var banAction: String { t("community.ban_action", "Ban") }
    static var warnTitle: String { t("community.warn_title", "Warning") }
    static func warnInfo(_ name: String) -> String {
        String(format: t("community.warn_info", "As a moderator you can send a warning message to **@%@**."), name)
    }
    static var message: String { t("community.message", "Message") }
    static func visibleBy(_ name: String) -> String {
        String(format: t("community.visible_by", "Your message, visible to @%@"), name)
    }
    static var shadowBanTitle: String { t("community.shadow_ban_title", "Shadow ban") }
    static func shadowBanInfo(_ name: String) -> String {
        String(format: t("community.shadow_ban_info", "**@%@** will be the only one to see their posts. They won’t be told their account was shadow banned."), name)
    }
    static var banTitle: String { t("community.ban_title", "Ban") }
    static func banInfo(_ name: String) -> String {
        String(format: t("community.ban_info", "**@%@** won’t be able to post, comment or react in the community anymore."), name)
    }
    static var chooseDuration: String { t("community.choose_duration", "Choose the duration") }
    static var durationPermanent: String { t("community.duration_permanent", "Permanent") }
    static var durationOneDay: String { t("community.duration_one_day", "24 hours") }
    static var durationSevenDays: String { t("community.duration_seven_days", "7 days") }
    static var durationThirtyDays: String { t("community.duration_thirty_days", "30 days") }
    static var motive: String { t("community.motive", "Reason") }
    static var teamOnlyPlaceholder: String { t("community.team_only_placeholder", "Only for you and your team.") }
    static func characterCounter(_ count: Int, _ limit: Int) -> String {
        String(format: t("community.character_counter", "%d/%d"), count, limit)
    }
    static var notificationTitle: String { t("community.notification_title", "Notification") }
    static var understood: String { t("community.understood", "Got it") }
    static var postRemovedSection: String { t("community.post_removed_section", "Your post was deleted because it breaks a community rule.") }
    static var commentRemovedSection: String { t("community.comment_removed_section", "Your comment was deleted because it breaks a community rule.") }
    static var tempBanSection: String { t("community.temp_ban_section", "Your account was temporarily banned because it breaks the community rules.") }
    static var banSection: String { t("community.ban_section", "Your account was banned because it breaks the community rules.") }
    static var banDefaultBody: String { t("community.ban_default_body", "Your account was banned after several problematic posts.") }
    static func tempBanLabel(_ date: String) -> String {
        String(format: t("community.temp_ban_label", "Temporary ban (until %@)"), date)
    }
    static var permanentBanLabel: String { t("community.permanent_ban_label", "Permanent ban") }
    static func warnSection(_ team: String) -> String {
        String(format: t("community.warn_section", "An admin of the %@ team sent you a warning."), team)
    }
    static var removedFallbackReason: String { t("community.removed_fallback_reason", "Community rules") }
    static var postRemovedAlertTitle: String { t("community.post_removed_alert_title", "Post deleted") }
    static var commentRemovedAlertTitle: String { t("community.comment_removed_alert_title", "Comment deleted") }
    static var postRemovedAlertMessage: String { t("community.post_removed_alert_message", "This content breaks a community rule. You’ll find why in your notifications.") }
    static var openModeration: String { t("community.open_moderation", "Moderation") }
    static var openSanctions: String { t("community.open_sanctions", "Notifications") }
    static var anonymousBannerTitle: String { t("community.anonymous_banner_title", "Your profile is anonymous") }
    static var editProfileShort: String { t("community.edit_profile_short", "Edit profile") }
    static var anonymousPseudo: String { t("community.anonymous_pseudo", "Anonymous name") }
    static var nicknamePlaceholder: String { t("community.nickname_placeholder", "Your name") }
    static var dismiss: String { t("community.dismiss", "Dismiss") }
    static var deleteCommentTitle: String { t("community.delete_comment_title", "Delete this comment?") }
    static var actionFailed: String { t("community.action_failed", "That didn’t work. Try again.") }

    static func duration(_ duration: SanctionDuration) -> String {
        switch duration {
        case .permanent: return durationPermanent
        case .oneDay: return durationOneDay
        case .sevenDays: return durationSevenDays
        case .thirtyDays: return durationThirtyDays
        }
    }

    static func reactionLabel(_ kind: CommunityReactionKind) -> String {
        switch kind {
        case .love: return t("community.reaction_love", "Love")
        case .like: return t("community.reaction_like", "Like")
        case .laugh: return t("community.reaction_laugh", "Laugh")
        case .fire: return t("community.reaction_fire", "Fire")
        case .wow: return t("community.reaction_wow", "Wow")
        case .clap: return t("community.reaction_clap", "Clap")
        case .eyes: return t("community.reaction_eyes", "Eyes")
        case .sad: return t("community.reaction_sad", "Sad")
        case .pray: return t("community.reaction_pray", "Pray")
        case .bangbang: return t("community.reaction_bangbang", "Wow!")
        case .angry: return t("community.reaction_angry", "Angry")
        }
    }

    static func reportReason(_ reason: CommunityReportReason) -> String {
        reasonLabel(reason.rawValue)
    }

    static func moderationReason(_ reason: ModerationReason) -> String {
        reasonLabel(reason.rawValue)
    }

    /// A reason key (report or moderation) as a label; a moderator's free text stays as typed.
    static func reasonLabel(_ raw: String) -> String {
        switch raw {
        case "hate_speech": return t("community.reason_hate_speech", "Hate speech, discrimination or harassment")
        case "sexual_content": return t("community.reason_sexual_content", "Sexual or inappropriate content")
        case "violence": return t("community.reason_violence", "Violence and terrorism")
        case "spam": return t("community.reason_spam", "Spam and scams")
        case "self_harm": return t("community.reason_self_harm", "Self-harm or suicide")
        case "child_safety": return t("community.reason_child_safety", "Child exploitation or abuse")
        case "intellectual_property": return t("community.reason_intellectual_property", "Intellectual property infringement")
        case "impersonation": return t("community.reason_impersonation", "Fake profiles or impersonation")
        case "other": return t("community.reason_other", "Other")
        case "dissatisfaction": return t("community.reason_dissatisfaction", "Dissatisfaction with the product")
        case "support": return t("community.reason_support", "Question for support")
        case "personal_data": return t("community.reason_personal_data", "Sharing of personal data")
        case "duplicate": return t("community.reason_duplicate", "Content posted twice")
        case "harassment": return t("community.reason_harassment", "Harassment")
        case "misinformation": return t("community.reason_misinformation", "Misinformation")
        case "off_topic": return t("community.reason_off_topic", "Off topic")
        default: return raw
        }
    }
}
