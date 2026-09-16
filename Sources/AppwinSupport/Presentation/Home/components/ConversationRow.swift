//
//  ConversationRow.swift
//  AppwinSupport
//
//  Inbox row: agent avatar, preview, relative time, unread badge.
//

import SwiftUI

struct ConversationRow: View {
    let conversation: Conversation

    @Environment(\.appwinTheme) private var theme
    @EnvironmentObject private var configStore: ConfigStore
    @EnvironmentObject private var session: AppwinSession

    private let cardBorder = Color(hex: 0xF1F5F9)

    private var hasUnread: Bool { conversation.hasUnread }

    private var previewLabel: String {
        let raw = conversation.preview?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        if raw.isEmpty { return SupportStrings.newConversationPreview }
        if let media = Self.mediaLabel(raw) { return media }
        return raw
    }

    var body: some View {
        HStack(alignment: .center, spacing: 12) {
            // Padding keeps the unread dot inside the card bounds: an offset
            // alone was drawn outside the avatar then clipped by the card shape.
            ZStack(alignment: .topTrailing) {
                AppwinAvatar(
                    name: configStore.config.context.agentName,
                    avatarURL: configStore.config.context.agentAvatarUrl,
                    size: 44,
                    font: .system(size: 14, weight: .semibold),
                    fallbackStyle: .project
                )

                if hasUnread {
                    Circle()
                        .fill(theme.colors.accent)
                        .frame(width: 10, height: 10)
                        .overlay(Circle().stroke(Color.white, lineWidth: 2))
                        .offset(x: 2, y: -2)
                }
            }
            .padding(.top, 2)
            .padding(.trailing, 2)

            VStack(alignment: .leading, spacing: 4) {
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Text(configStore.config.context.agentName)
                        .font(.system(size: 14, weight: hasUnread ? .semibold : .medium))
                        .foregroundColor(AppwinTokens.textHigh)
                        .lineLimit(1)

                    Spacer(minLength: 4)

                    Text(relativeTime)
                        .font(.system(size: 11, weight: .medium))
                        .foregroundColor(hasUnread ? theme.colors.accent : AppwinTokens.textLow)
                        .fixedSize()
                }

                HStack(alignment: .top, spacing: 6) {
                    Text(previewAttributed(previewLabel))
                        .font(.system(size: 13, weight: hasUnread ? .medium : .regular))
                        .foregroundColor(hasUnread ? AppwinTokens.textHigh : AppwinTokens.textMedium)
                        .lineLimit(3)
                        .truncationMode(.tail)
                        .multilineTextAlignment(.leading)
                        .frame(maxWidth: .infinity, alignment: .leading)

                    SolarIcon(kind: .altArrowRight, color: AppwinTokens.textLow, size: 14)
                        .padding(.top, 2)
                }

                if conversation.status == .resolved || conversation.status == .closed {
                    statusChip
                }
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

    private var statusChip: some View {
        Text(conversation.status == .resolved ? SupportStrings.statusResolved : SupportStrings.statusClosed)
            .font(.system(size: 10, weight: .semibold))
            .foregroundColor(AppwinTokens.textMedium)
            .padding(.horizontal, 8)
            .padding(.vertical, 3)
            .background(AppwinTokens.surfaceMuted)
            .clipShape(Capsule())
    }

    private var relativeTime: String {
        formatRelative(conversation.lastMessageAt ?? conversation.createdAt)
    }

    private func previewAttributed(_ raw: String) -> AttributedString {
        if Self.mediaLabel(raw) != nil {
            return AttributedString(raw)
        }
        return MarkdownText.previewAttributed(raw, linkColor: theme.colors.accent)
    }

    /// Photo, Video or File, inferred from the server-side filename.
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

    private func formatRelative(_ date: Date) -> String {
        let language = SupportDisplayLocale.uiLanguage(customerLanguage: nil)
        let locale = SupportDisplayLocale.locale(languageCode: language)
        let calendar = Calendar.current
        if calendar.isDateInToday(date) {
            let f = DateFormatter()
            f.locale = locale
            f.timeStyle = .short
            f.dateStyle = .none
            return f.string(from: date)
        }
        if calendar.isDateInYesterday(date) {
            return SupportStrings.yesterday(language: language)
        }
        let f = DateFormatter()
        f.locale = locale
        if calendar.component(.year, from: date) == calendar.component(.year, from: Date()) {
            f.dateFormat = "d MMM"
        } else {
            f.dateFormat = "d MMM yyyy"
        }
        return f.string(from: date)
    }
}
