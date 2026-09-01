//
//  MessageBubble.swift
//  AppwinSupport
//
//  Bulle de chat - pixel-match SaaS `ChatBubble` :
//  customer (moi) → droite, bg-main #0E172A ; agent → gauche, bg-subtle.
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

    @EnvironmentObject private var configStore: ConfigStore
    @EnvironmentObject private var session: AppwinSession

    private var isCustomer: Bool { message.authorType == .customer }
    private var agentName: String { configStore.config.context.agentName }
    private var agentAvatarURL: URL? { configStore.config.context.agentAvatarUrl }
    private var customerName: String? { session.customer?.name ?? message.authorName }

    private let avatarSize: CGFloat = 20
    private let bubbleRadius: CGFloat = 16
    /// Avatar plus gap: the footer's offset under the bubble.
    private var footerIndent: CGFloat { avatarSize + 8 }

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
            HStack(alignment: .bottom, spacing: 8) {
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
    private func bubbleColumn(alignment: HorizontalAlignment) -> some View {
        VStack(alignment: alignment, spacing: 6) {
            if !message.body.isEmpty {
                bubbleWithReactions
            } else if !message.reactions.isEmpty {
                reactionChip
            }
            attachmentsView
        }
        .contextMenu {
            reactionMenu
            if isCustomer {
                Divider()
                messageActions
            }
        }
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

    @ViewBuilder
    private var reactionMenu: some View {
        ForEach(QuickMessageReactions.all, id: \.self) { emoji in
            Button {
                onToggleReaction?(emoji)
            } label: {
                let mine = message.reactions.contains { $0.emoji == emoji && $0.reactedByMe }
                Text(mine ? "\(emoji) ✓" : emoji)
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

    @ViewBuilder
    private var messageActions: some View {
        if !message.body.isEmpty, let onEdit {
            Button { onEdit() } label: {
                Label("Modifier mon message", systemImage: "pencil")
            }
        }
        if let onDelete {
            Button(role: .destructive) { onDelete() } label: {
                Label("Supprimer mon message", systemImage: "trash")
            }
        }
    }

    private var bubbleText: some View {
        MarkdownText(
            message.body,
            color: isCustomer ? AppwinTokens.textOnBrand : AppwinTokens.textHigh,
            bodyFont: .system(size: 14, weight: .medium)
        )
        .padding(12)
        .background(bubbleFill)
        .clipShape(RoundedRectangle(cornerRadius: bubbleRadius, style: .continuous))
    }

    private var bubbleFill: Color {
        isCustomer ? AppwinTokens.surfaceInverse : AppwinTokens.surfaceMuted
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
                Text(message.readAt != nil ? "Vu" : "Envoyé")
                Text("·")
            }
            Text(timeText)
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
            fallbackFill: AppwinTokens.surfaceMuted
        )
        .offset(y: avatarOffsetY)
    }

    private var customerAvatar: some View {
        AppwinAvatar(
            name: customerName,
            avatarURL: nil,
            size: avatarSize,
            font: .system(size: 8, weight: .semibold),
            fallbackFill: AppwinTokens.surfaceMuted,
            fallbackForeground: AppwinTokens.textHigh
        )
        .offset(y: avatarOffsetY)
    }

    private var timeText: String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "fr_FR")
        formatter.dateFormat = "H'h'mm"
        return formatter.string(from: message.createdAt)
    }
}
