//
//  RecentMessageCard.swift
//  AppwinSupport
//
//  Intercom-style home teaser: jump back into the latest open conversation.
//

import SwiftUI

struct RecentMessageCard: View {
  let conversation: Conversation

  @Environment(\.appwinTheme) private var theme
  @EnvironmentObject private var configStore: ConfigStore
  @EnvironmentObject private var session: AppwinSession

  private let cardBorder = Color(hex: 0xF1F5F9)

  private var previewLabel: String {
    let raw = conversation.preview?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
    let body: String = {
      if raw.isEmpty { return SupportStrings.newConversationPreview }
      if let media = Self.mediaLabel(raw) { return media }
      return raw
    }()
    // Intercom: make it obvious the last line was yours.
    if conversation.lastMessageAuthorType == .customer {
      return SupportStrings.youPreview(body, language: SupportDisplayLocale.uiLanguage(customerLanguage: nil))
    }
    return body
  }

  private var metaLine: String {
    let agent = configStore.config.context.agentName
    let when = SupportRelativeAge.format(
      conversation.lastMessageAt ?? conversation.createdAt,
      language: SupportDisplayLocale.uiLanguage(customerLanguage: nil)
    )
    if when.isEmpty { return agent }
    return "\(agent) · \(when)"
  }

  var body: some View {
    VStack(alignment: .leading, spacing: 10) {
      Text(SupportStrings.recentMessage)
        .font(.system(size: 13, weight: .semibold))
        .foregroundColor(AppwinTokens.textHigh)

      HStack(alignment: .center, spacing: 12) {
        // Padding keeps the unread dot inside the card (same as ConversationRow).
        ZStack(alignment: .topTrailing) {
          AppwinAvatar(
            name: configStore.config.context.agentName,
            avatarURL: configStore.config.context.agentAvatarUrl,
            size: 40,
            font: .system(size: 13, weight: .semibold),
            fallbackStyle: .project
          )
          if conversation.hasUnread {
            Circle()
              .fill(theme.colors.accent)
              .frame(width: 10, height: 10)
              .overlay(Circle().stroke(Color.white, lineWidth: 2))
              .offset(x: 2, y: -2)
          }
        }
        .padding(.top, 2)
        .padding(.trailing, 2)

        VStack(alignment: .leading, spacing: 2) {
          Text(previewLabel)
            .font(.system(size: 14, weight: conversation.hasUnread ? .semibold : .medium))
            .foregroundColor(AppwinTokens.textHigh)
            .lineLimit(3)
            .truncationMode(.tail)
            .multilineTextAlignment(.leading)
            .frame(maxWidth: .infinity, alignment: .leading)

          Text(metaLine)
            .font(.system(size: 12, weight: .regular))
            .foregroundColor(conversation.hasUnread ? theme.colors.accent : AppwinTokens.textMedium)
            .lineLimit(1)
        }

        Spacer(minLength: 4)

        SolarIcon(kind: .altArrowRight, color: AppwinTokens.textLow, size: 14)
      }
    }
    .padding(14)
    .frame(maxWidth: .infinity, alignment: .leading)
    .background(
      Color.white,
      in: RoundedRectangle(cornerRadius: theme.radius.card, style: .continuous)
    )
    .overlay(
      RoundedRectangle(cornerRadius: theme.radius.card, style: .continuous)
        .strokeBorder(cardBorder, lineWidth: 1)
    )
    .shadow(color: AppwinTokens.shadowSmooth, radius: 2, x: 0, y: 2)
    .contentShape(RoundedRectangle(cornerRadius: theme.radius.card, style: .continuous))
  }

  private static func mediaLabel(_ s: String) -> String? {
    let t = s.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !t.isEmpty, !t.contains(" "), let dot = t.lastIndex(of: ".") else { return nil }
    let ext = String(t[t.index(after: dot)...]).lowercased()
    guard (1...5).contains(ext.count), ext.allSatisfy({ $0.isLetter || $0.isNumber }) else {
      return nil
    }
    if ["jpg", "jpeg", "png", "gif", "webp", "heic"].contains(ext) { return SupportStrings.mediaPhoto }
    if ["mp4", "mov", "m4v", "webm"].contains(ext) { return SupportStrings.mediaVideo }
    if ext == "pdf" { return SupportStrings.mediaPdf }
    return SupportStrings.mediaFile
  }
}

/// Intercom-style relative age for the home recent card (`Just now`, `5m`, …).
enum SupportRelativeAge {
  static func format(_ date: Date, language: String?, now: Date = Date()) -> String {
    let seconds = max(0, Int(now.timeIntervalSince(date)))
    if seconds < 60 { return SupportStrings.justNow(language: language) }
    if seconds < 3_600 {
      return String(format: SupportStrings.relativeMinutes(language: language), seconds / 60)
    }
    if seconds < 86_400 {
      return String(format: SupportStrings.relativeHours(language: language), seconds / 3_600)
    }
    if seconds < 604_800 {
      return String(format: SupportStrings.relativeDays(language: language), seconds / 86_400)
    }
    return String(format: SupportStrings.relativeWeeks(language: language), seconds / 604_800)
  }
}
