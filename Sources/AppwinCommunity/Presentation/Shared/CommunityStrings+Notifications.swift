import Foundation

// Labels of the bell's inbox. The actor's nickname is bold (`**%@**`).

extension CommunityStrings {
    static var notificationsTitle: String { t("community.notifications_title", "Notifications") }
    static var notificationsEmpty: String { t("community.notifications_empty", "No notifications yet") }
    static var notificationsEmptyHint: String {
        t("community.notifications_empty_hint", "Comments, replies and likes on your posts show up here.")
    }
    static var activitySomeone: String { t("community.activity_someone", "Someone") }

    /// « 1 other » / « 3 others », after the first actor's name.
    static func activityOthers(_ count: Int) -> String {
        count == 1
            ? t("community.activity_others_one", "1 other")
            : String(format: t("community.activity_others_many", "%d others"), count)
    }

    /// Markdown sentence of an inbox entry; `others` is set when the entry
    /// groups several members.
    static func activitySentence(_ type: CommunityNotificationType, actor: String, others: String?) -> String {
        let (key, fallback): (String, String)
        switch (type, others != nil) {
        case (.postComment, _):
            (key, fallback) = ("community.activity_commented", "**%@** commented on your post")
        case (.commentReply, _):
            (key, fallback) = ("community.activity_replied", "**%@** replied to your comment")
        case (.adminPost, _):
            (key, fallback) = ("community.activity_admin_post", "**%@** posted an announcement")
        case (.postReaction, false):
            (key, fallback) = ("community.activity_liked_post", "**%@** liked your post")
        case (.postReaction, true):
            (key, fallback) = ("community.activity_liked_post_group", "**%@** and %@ liked your post")
        case (.commentReaction, false):
            (key, fallback) = ("community.activity_liked_comment", "**%@** liked your comment")
        case (.commentReaction, true):
            (key, fallback) = ("community.activity_liked_comment_group", "**%@** and %@ liked your comment")
        case (.pollVote, false):
            (key, fallback) = ("community.activity_voted", "**%@** voted in your poll")
        case (.pollVote, true):
            (key, fallback) = ("community.activity_voted_group", "**%@** and %@ voted in your poll")
        default:
            return ""
        }
        let format = t(key, fallback)
        if let others { return String(format: format, actor, others) }
        return String(format: format, actor)
    }
}
