import Foundation

enum SupportStrings {
  private static func t(_ key: String, _ fallback: String, language: String? = nil) -> String {
    let bundle = SupportDisplayLocale.bundle(languageCode: language, resources: resourceBundle)
    return NSLocalizedString(key, tableName: "AppwinSupport", bundle: bundle, value: fallback, comment: "")
  }

  private static var resourceBundle: Bundle {
    #if SWIFT_PACKAGE
    .module
    #else
    Bundle.appwinSupportResources
    #endif
  }

  static var title: String { t("support.title", "Help") }
  static var close: String { t("support.close", "Close") }
  static var retry: String { t("support.retry", "Retry") }
  static var send: String { t("support.send", "Send") }
  static var newConversation: String { t("support.newConversation", "Send us a message") }
  static var conversations: String { t("support.conversations", "Your conversations") }
  static var conversationsTitle: String { t("support.conversationsTitle", "My conversations") }
  static var messaging: String { t("support.messaging", "Your inbox") }
  static var noConversation: String { t("support.noConversation", "No conversation yet") }
  static var emptyConversationsHint: String {
    t("support.emptyConversationsHint", "Write to support to get started - we reply here.")
  }
  static var writeMessage: String { t("support.writeMessage", "Write a message") }
  static var faq: String { t("support.faq", "Help centre") }
  static var greetingNamed: String { t("support.greetingNamed", "Hello %@ 👋") }
  static var greetingYou: String { t("support.greetingYou", "you") }
  static var greetingSubtitle: String { t("support.greetingSubtitle", "Need help?") }
  static var messagePlaceholder: String { t("support.messagePlaceholder", "Write a message…") }
  static var loadErrorTitle: String { t("support.loadErrorTitle", "Couldn't load") }
  static var loadErrorMessage: String {
    t("support.loadErrorMessage", "Check your connection and try again.")
  }
  static var openFailed: String { t("support.openFailed", "Couldn't open support.") }
  static var openFailedDetail: String { t("support.openFailedDetail", "Couldn't open support: %@") }
  static var notConfigured: String {
    t("support.notConfigured", "Appwin is not configured (missing configure).")
  }
  static var temporarilyUnavailable: String {
    t("support.temporarilyUnavailable", "Support is temporarily unavailable.")
  }
  static var planUnavailable: String {
    t("support.planUnavailable", "Support is not included in this organisation's plan.")
  }
  static var disabledUnavailable: String {
    t(
      "support.disabledUnavailable",
      "Support is disabled for this app. Enable it in the Appwin dashboard."
    )
  }
  static var statusResolved: String { t("support.statusResolved", "Resolved") }
  static var statusClosed: String { t("support.statusClosed", "Closed") }
  static func seen(language: String?) -> String { t("support.seen", "Seen", language: language) }
  static func sent(language: String?) -> String { t("support.sent", "Sent", language: language) }
  static var newConversationPreview: String { t("support.newConversationPreview", "New conversation") }
  static var mediaPhoto: String { t("support.mediaPhoto", "Photo") }
  static var mediaVideo: String { t("support.mediaVideo", "Video") }
  static var mediaPdf: String { t("support.mediaPdf", "PDF") }
  static var mediaFile: String { t("support.mediaFile", "File") }
  static func yesterday(language: String?) -> String {
    t("support.yesterday", "Yesterday", language: language)
  }
  static func today(language: String?) -> String {
    t("support.today", "Today", language: language)
  }
  static var back: String { t("support.back", "Back") }
  static var noArticles: String { t("support.noArticles", "No articles") }
  static var faqMore: String { t("support.faqMore", "+%d more") }
  static var editMessage: String { t("support.editMessage", "Edit") }
  static var deleteMessage: String { t("support.deleteMessage", "Delete") }
  static var editingBanner: String { t("support.editingBanner", "Editing message") }
  static var cancel: String { t("support.cancel", "Cancel") }
  static var attachImage: String { t("support.attachImage", "Add an image") }
  static var attachVideo: String { t("support.attachVideo", "Add a video") }
  static var attachFile: String { t("support.attachFile", "Attach a file") }
  static var emoji: String { t("support.emoji", "Emoji") }
  static var save: String { t("support.save", "Save") }
  static var typing: String { t("support.typing", "Typing") }
  static var openFile: String { t("support.openFile", "Open %@") }
  static var agentFallback: String { t("support.agentFallback", "Support") }
  static var messengerOpenFailed: String {
    t("support.messengerOpenFailed", "The messenger could not open")
  }
  static var sendToSupport: String { t("support.sendToSupport", "Send a message to support") }
  static var recentMessage: String { t("support.recentMessage", "Recent message") }
  /// Preview line when the customer wrote last (`You: …`).
  static func youPreview(_ body: String, language: String? = nil) -> String {
    String(format: t("support.youPreview", "You: %@", language: language), body)
  }
  static func justNow(language: String?) -> String {
    t("support.justNow", "Just now", language: language)
  }
  static func relativeMinutes(language: String?) -> String {
    t("support.relativeMinutes", "%dm", language: language)
  }
  static func relativeHours(language: String?) -> String {
    t("support.relativeHours", "%dh", language: language)
  }
  static func relativeDays(language: String?) -> String {
    t("support.relativeDays", "%dd", language: language)
  }
  static func relativeWeeks(language: String?) -> String {
    t("support.relativeWeeks", "%dw", language: language)
  }
  static var errorPrefix: String { t("support.errorPrefix", "Error: %@") }
  static var showOriginal: String { t("support.showOriginal", "Show original") }
  static var seeTranslation: String { t("support.seeTranslation", "See translation") }

  /// Device-locale fallbacks when no customer language is available.
  static var seen: String { seen(language: nil) }
  static var sent: String { sent(language: nil) }
  static var yesterday: String { yesterday(language: nil) }
  static var today: String { today(language: nil) }
}
