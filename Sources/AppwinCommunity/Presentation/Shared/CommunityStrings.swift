import Foundation

/// SDK labels.
///
/// The SDK is embedded in apps of many languages: hard-coding the strings would
/// make the feed English inside a French app.
///
/// Resolution happens in the **host app's** bundle, not the package's. Two
/// consequences, both intended:
///
///  - the studio translates the SDK by adding the `community.*` keys to its own
///    `AppwinCommunity.strings`, without waiting for us to ship its language;
///  - it can also rewrite a label that does not match its tone by overriding
///    the key.
///
/// With no file supplied, `NSLocalizedString` returns the `value:` - the English
/// default below. A raw key is never displayed.
///
/// Distinct des catalogues du dashboard : deux surfaces, deux publics (le
/// studio on one side, its users on the other).
enum CommunityStrings {
    private static func t(_ key: String, _ fallback: String) -> String {
        NSLocalizedString(
            key,
            tableName: "AppwinCommunity",
            bundle: .main,
            value: fallback,
            comment: ""
        )
    }

    // General
    static var teamBadge: String { t("community.team_badge", "Team") }
    static var retry: String { t("community.retry", "Retry") }
    static var cancel: String { t("community.cancel", "Cancel") }
    static var delete: String { t("community.delete", "Delete") }
    static var send: String { t("community.send", "Send") }
    static var close: String { t("community.close", "Close") }
    static var seeMore: String { t("community.see_more", "See more") }
    static var seeLess: String { t("community.see_less", "See less") }

    // Fil
    static var title: String { t("community.title", "Community") }
    static var allGroups: String { t("community.all_groups", "For you") }
    static var newPost: String { t("community.new_post", "Create a post") }
    static var emptyFeedTitle: String { t("community.empty_feed_title", "Nothing here yet") }
    static var emptyFeedMessage: String {
        t("community.empty_feed_message", "Be the first to share something with the community.")
    }
    static var disabledTitle: String { t("community.disabled_title", "Coming soon") }
    static var disabledMessage: String {
        t("community.disabled_message", "The community is not open yet. Come back a bit later.")
    }
    static var loadErrorTitle: String { t("community.load_error_title", "Couldn't load") }
    static var loadErrorMessage: String {
        t("community.load_error_message", "Check your connection and try again.")
    }

    // Post
    static var like: String { t("community.like", "Like") }
    static var comment: String { t("community.comment", "Comment") }
    static var pendingReview: String {
        t("community.pending_review", "Only you can see this post while it is being reviewed.")
    }
    static var translate: String { t("community.translate", "Translate") }
    static var showOriginal: String { t("community.show_original", "Show original") }
    static var deletePostTitle: String { t("community.delete_post_title", "Delete this post?") }
    static var deletePostMessage: String {
        t("community.delete_post_message", "It will be removed for everyone, along with its comments.")
    }

    // Commentaires
    static var comments: String { t("community.comments", "Comments") }
    static var noComments: String { t("community.no_comments", "No comments yet") }
    static var beFirstToComment: String {
        t("community.be_first_to_comment", "Start the conversation.")
    }
    static var addComment: String { t("community.add_comment", "Add a comment") }
    static var reply: String { t("community.reply", "Reply") }
    static var replyingTo: String { t("community.replying_to", "Replying to %@") }
    static func showReplies(_ count: Int) -> String {
        String(format: t("community.show_replies", "Show %d replies"), count)
    }

    // Composeur
    static var composerPlaceholder: String {
        t("community.composer_placeholder", "What do you want to share?")
    }
    static var publish: String { t("community.publish", "Publish") }
    static var chooseGroup: String { t("community.choose_group", "Group") }

    // Profil
    static var profile: String { t("community.profile", "Profile") }
    static var editProfile: String { t("community.edit_profile", "Edit profile") }
    static var nickname: String { t("community.nickname", "Nickname") }
    static var bio: String { t("community.bio", "Bio") }
    static var save: String { t("community.save", "Save") }
    static var anonymous: String { t("community.anonymous", "Stay anonymous") }
    static var memberSince: String { t("community.member_since", "Member since %@") }
    static func postCount(_ count: Int) -> String {
        String(format: t("community.post_count", "%d posts"), count)
    }
    static func commentCount(_ count: Int) -> String {
        String(format: t("community.comment_count", "%d comments"), count)
    }
    static func reactionCount(_ count: Int) -> String {
        String(format: t("community.reaction_count", "%d likes"), count)
    }
    static var noPostsYet: String { t("community.no_posts_yet", "No posts yet") }
    static var bannedNotice: String {
        t("community.banned_notice", "Your account is restricted. You can read but not post.")
    }

    // Signalement
    static var report: String { t("community.report", "Report") }
    static var reportTitle: String { t("community.report_title", "Report this content") }
    static var reportSent: String { t("community.report_sent", "Thanks, we'll take a look.") }
    static func reportReason(_ reason: CommunityReportReason) -> String {
        switch reason {
        case .spam: return t("community.reason_spam", "Spam")
        case .harassment: return t("community.reason_harassment", "Harassment")
        case .hateSpeech: return t("community.reason_hate_speech", "Hate speech")
        case .sexualContent: return t("community.reason_sexual_content", "Sexual content")
        case .violence: return t("community.reason_violence", "Violence")
        case .misinformation: return t("community.reason_misinformation", "Misinformation")
        case .offTopic: return t("community.reason_off_topic", "Off topic")
        case .other: return t("community.reason_other", "Something else")
        }
    }
}
