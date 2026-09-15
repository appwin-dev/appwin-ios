//
//  MessageBubble.swift
//  AppwinSupport
//
//  Chat bubble: the customer sits on the right on the studio's accent colour,
//  the agent on the left on white. Each bubble squares off the corner facing
//  its own avatar, which is what reads as a tail.
//  The avatar sits at the bottom of the bubble, not of the timestamp.
//

import SwiftUI
import AppwinCore

struct MessageBubble: View {
    let message: Message
    var showFooter: Bool = true
    var showAvatar: Bool = true
    var showReadReceipt: Bool = false
    var onEdit: (() -> Void)? = nil
    var onDelete: (() -> Void)? = nil
    var onToggleReaction: ((String) -> Void)? = nil
    /// Owned by `MessageList` so a tap on the thread background can dismiss it.
    @Binding var showReactionPicker: Bool

    @Environment(\.appwinTheme) private var theme
    @EnvironmentObject private var configStore: ConfigStore
    @EnvironmentObject private var session: AppwinSession
    @State private var showsOriginal = false
    /// Swallow the finger-up tap that follows a successful long-press, otherwise
    /// the picker opens and the same gesture's tap closes it immediately.
    @State private var suppressPickerDismissTap = false

    private var isCustomer: Bool { message.authorType == .customer }
    private var agentName: String { configStore.config.context.agentName }
    private var agentAvatarURL: URL? { configStore.config.context.agentAvatarUrl }
    private var customerName: String? { session.customer?.name ?? message.authorName }

    private var canEditOrDelete: Bool {
        isCustomer && (onEdit != nil || onDelete != nil) && !message.body.isEmpty
    }

    /// Studio replies: show the customer-language translation by default.
    private var hasTranslation: Bool {
        guard !isCustomer,
              let translated = message.translatedBody?.trimmingCharacters(in: .whitespacesAndNewlines),
              !translated.isEmpty,
              translated != message.body
        else { return false }
        return true
    }

    private var displayBody: String {
        if hasTranslation, !showsOriginal, let translated = message.translatedBody {
            return translated
        }
        return message.body
    }

    private let avatarSize: CGFloat = 20
    private let bubbleRadius: CGFloat = 16
    private let rowSpacing: CGFloat = 4
    /// Avatar plus gap: the footer's offset under the bubble.
    private var footerIndent: CGFloat { avatarSize + rowSpacing }

    /// Text only, with no image, video or file, sits the avatar slightly higher.
    private var isTextOnly: Bool { message.attachments.isEmpty }
    private var avatarOffsetY: CGFloat { isTextOnly ? -3 : -2 }

    private var reactionSummary: (emojis: [String], extra: Int) {
        let sorted = message.reactions.sorted {
            $0.count != $1.count ? $0.count > $1.count : $0.emoji < $1.emoji
        }
        if sorted.count <= 2 {
            return (sorted.map(\.emoji), 0)
        }
        return (Array(sorted.prefix(2).map(\.emoji)), sorted.count - 2)
    }

    var body: some View {
        VStack(alignment: isCustomer ? .trailing : .leading, spacing: 6) {
            if showReactionPicker {
                messageActionChrome
            }

            HStack(alignment: .bottom, spacing: rowSpacing) {
                if isCustomer {
                    Spacer(minLength: 48)
                    bubbleColumn(alignment: .trailing)
                    if showAvatar {
                        customerAvatar
                    } else {
                        Color.clear.frame(width: avatarSize, height: avatarSize)
                    }
                } else {
                    if showAvatar {
                        agentAvatar
                    } else {
                        Color.clear.frame(width: avatarSize, height: avatarSize)
                    }
                    bubbleColumn(alignment: .leading)
                    Spacer(minLength: 48)
                }
            }

            if showFooter {
                footer
                    .padding(isCustomer ? .trailing : .leading, footerIndent)
            }
        }
    }

    @ViewBuilder
    private var messageActionChrome: some View {
        VStack(alignment: isCustomer ? .trailing : .leading, spacing: 8) {
            reactionPickerPill
            if canEditOrDelete {
                editDeletePill
            }
        }
        .padding(isCustomer ? .trailing : .leading, footerIndent)
        .transition(.opacity.combined(with: .scale(scale: 0.96, anchor: isCustomer ? .bottomTrailing : .bottomLeading)))
    }

    private var reactionPickerPill: some View {
        HStack(spacing: 2) {
            ForEach(QuickMessageReactions.all, id: \.self) { emoji in
                let mine = message.reactions.contains { $0.emoji == emoji && $0.reactedByMe }
                Button {
                    onToggleReaction?(emoji)
                    showReactionPicker = false
                } label: {
                    Text(emoji)
                        .font(.system(size: 22))
                        .frame(width: 36, height: 36)
                        .background(mine ? AppwinTokens.surfaceMuted : Color.clear)
                        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 6)
        .background(AppwinTokens.surface)
        .clipShape(Capsule(style: .continuous))
        .shadow(color: Color.black.opacity(0.12), radius: 12, x: 0, y: 4)
    }

    private var editDeletePill: some View {
        HStack(spacing: 0) {
            if !message.body.isEmpty, let onEdit {
                Button {
                    showReactionPicker = false
                    onEdit()
                } label: {
                    Label(SupportStrings.editMessage, systemImage: "pencil")
                        .labelStyle(.titleAndIcon)
                        .font(.system(size: 13, weight: .medium))
                        .foregroundColor(AppwinTokens.textHigh)
                        .padding(.horizontal, 14)
                        .padding(.vertical, 10)
                }
                .buttonStyle(.plain)
            }

            if onEdit != nil, onDelete != nil, !message.body.isEmpty {
                Rectangle()
                    .fill(AppwinTokens.surfaceMuted)
                    .frame(width: 1, height: 20)
            }

            if let onDelete {
                Button {
                    showReactionPicker = false
                    onDelete()
                } label: {
                    Label(SupportStrings.deleteMessage, systemImage: "trash")
                        .labelStyle(.titleAndIcon)
                        .font(.system(size: 13, weight: .medium))
                        .foregroundColor(Color(red: 0.86, green: 0.15, blue: 0.15))
                        .padding(.horizontal, 14)
                        .padding(.vertical, 10)
                }
                .buttonStyle(.plain)
            }
        }
        .background(AppwinTokens.surface)
        .clipShape(Capsule(style: .continuous))
        .shadow(color: Color.black.opacity(0.12), radius: 12, x: 0, y: 4)
    }

    @ViewBuilder
    private func bubbleColumn(alignment: HorizontalAlignment) -> some View {
        VStack(alignment: alignment, spacing: 6) {
            if !displayBody.isEmpty {
                bubbleWithReactions
            } else if !message.reactions.isEmpty {
                reactionChip
            }
            attachmentsView
        }
        .contentShape(Rectangle())
        .onTapGesture {
            if suppressPickerDismissTap {
                suppressPickerDismissTap = false
                return
            }
            // Always clear: closes this picker or a sibling's via the list binding.
            showReactionPicker = false
        }
        .simultaneousGesture(
            // Short enough to feel instant; the old 0.35s made brief holds fail
            // to open, and the lift-tap then hid anything that did open.
            LongPressGesture(minimumDuration: 0.2).onEnded { _ in
                suppressPickerDismissTap = true
                showReactionPicker = true
            }
        )
    }

    private var bubbleWithReactions: some View {
        ZStack(alignment: isCustomer ? .bottomTrailing : .bottomLeading) {
            bubbleText
                .padding(.bottom, message.reactions.isEmpty ? 0 : 10)
            if !message.reactions.isEmpty {
                reactionChip
                    .offset(y: 10)
            }
        }
    }

    private var reactionChip: some View {
        let summary = reactionSummary
        return HStack(spacing: 2) {
            ForEach(summary.emojis, id: \.self) { emoji in
                Button {
                    onToggleReaction?(emoji)
                } label: {
                    Text(emoji)
                }
                .buttonStyle(.plain)
            }
            if summary.extra > 0 {
                Text("+\(summary.extra)")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundColor(AppwinTokens.textHigh)
            }
        }
        .padding(4)
        .background(AppwinTokens.surfaceMuted)
        .overlay(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .stroke(AppwinTokens.surface, lineWidth: 1.5)
        )
        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
        .font(.system(size: 12))
    }

    private var bubbleText: some View {
        MarkdownText(
            displayBody,
            color: isCustomer ? theme.colors.onAccent : AppwinTokens.textHigh,
            bodyFont: .system(size: 12, weight: .medium)
        )
        .padding(16)
        .background(bubbleFill)
        .clipShape(bubbleShape)
        // The agent bubble sits flat on the sheet; only the accent one lifts.
        .shadow(color: isCustomer ? AppwinTokens.shadowIntense : .clear, radius: 8, x: 0, y: 4)
        .id("\(message.id)-\(displayBody)-\(showsOriginal)")
    }

    /// Squares off the corner facing the author's avatar: flush for the agent,
    /// near-flush (2) for the customer, per the design.
    private var bubbleShape: UnevenRoundedRectangle {
        UnevenRoundedRectangle(
            topLeadingRadius: bubbleRadius,
            bottomLeadingRadius: isCustomer ? bubbleRadius : 0,
            bottomTrailingRadius: isCustomer ? 2 : bubbleRadius,
            topTrailingRadius: bubbleRadius,
            style: .continuous
        )
    }

    private var bubbleFill: Color {
        isCustomer ? theme.colors.accent : AppwinTokens.surface
    }

    @ViewBuilder
    private var attachmentsView: some View {
        VStack(alignment: isCustomer ? .trailing : .leading, spacing: 6) {
            ForEach(message.attachments) { att in
                if att.mimeType.hasPrefix("video/") {
                    VideoBubble(attachment: att)
                } else if att.mimeType.hasPrefix("image/") {
                    ImageBubble(attachment: att)
                } else {
                    FileBubble(attachment: att)
                }
            }
        }
    }

    private var footer: some View {
        HStack(spacing: 4) {
            if isCustomer && showReadReceipt {
                Text(
                    message.readAt != nil
                        ? SupportStrings.seen(language: SupportDisplayLocale.uiLanguage(customerLanguage: nil))
                        : SupportStrings.sent(language: SupportDisplayLocale.uiLanguage(customerLanguage: nil))
                )
                Text("·")
            }
            Text(timeText)
            if hasTranslation {
                Text("·")
                Button {
                    showsOriginal.toggle()
                } label: {
                    Text(showsOriginal ? SupportStrings.seeTranslation : SupportStrings.showOriginal)
                        .underline()
                }
                .buttonStyle(.plain)
            }
        }
        .font(.system(size: 10, weight: .medium))
        .foregroundColor(AppwinTokens.textLow)
    }

    private var agentAvatar: some View {
        AppwinAvatar(
            name: agentName,
            avatarURL: agentAvatarURL,
            size: avatarSize,
            font: .system(size: 8, weight: .semibold),
            fallbackStyle: .project
        )
        .offset(y: avatarOffsetY)
    }

    private var customerAvatar: some View {
        AppwinAvatar(
            name: customerName,
            avatarURL: session.customer?.avatarUrl.flatMap(URL.init(string:)),
            size: avatarSize,
            font: .system(size: 8, weight: .semibold),
            fallbackFill: AppwinTokens.surfaceMuted,
            fallbackForeground: AppwinTokens.textHigh
        )
        .offset(y: avatarOffsetY)
    }

    private var timeText: String {
        let formatter = DateFormatter()
        formatter.locale = SupportDisplayLocale.locale(languageCode: nil)
        formatter.timeStyle = .short
        formatter.dateStyle = .none
        return formatter.string(from: message.createdAt)
    }
}
