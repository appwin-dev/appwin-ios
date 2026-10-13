import SwiftUI

/// One item of the moderation queue (Figma 182:857): why it is there, the
/// content as members see it with its sanction, and the two decisions.
struct ModerationQueueCard: View {
    let item: ModerationQueueItem
    let isBusy: Bool
    let failed: Bool
    let onDecide: (ModerationAction) -> Void
    let onShowReports: () -> Void

    @EnvironmentObject private var session: CommunitySession
    @Environment(\.communityTheme) private var theme

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            // Figma « motif »: a tab overlapping the card's top edge.
            VStack(alignment: .leading, spacing: -8) {
                cause.zIndex(1)
                content
            }
            HStack(spacing: 8) {
                backButton
                confirmButton
            }
            .disabled(isBusy)
            .opacity(isBusy ? 0.5 : 1)
            if failed { CommunityErrorLine() }
        }
    }

    // MARK: - Cause

    /// The classifier's category first: it acted alone, members' reports did not.
    @ViewBuilder
    private var cause: some View {
        if let category = item.aiCategories.first {
            causeLabel(
                icon: .dangerTriangle,
                text: CommunityStrings.reasonLabel(category),
                color: Self.isHarmful(category) ? AppwinCommunityPalette.alert : AppwinCommunityPalette.caution
            )
        } else if !item.reports.isEmpty {
            Button(action: onShowReports) {
                causeLabel(
                    icon: .flag,
                    text: item.reports.count == 1
                        ? CommunityStrings.reportsCountOne(1)
                        : CommunityStrings.reportsCount(item.reports.count),
                    color: AppwinCommunityPalette.caution
                )
            }
            .buttonStyle(.plain)
        }
    }

    private func causeLabel(icon: CommunityIcon, text: String, color: Color) -> some View {
        HStack(spacing: 2) {
            CommunityIconView(icon: icon, size: 12, color: color)
            Text(text)
                .font(theme.font(10, weight: .semibold))
                .foregroundStyle(color)
                .lineLimit(1)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 6)
        .background(theme.colors.surface, in: RoundedRectangle(cornerRadius: 8))
        .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(theme.colors.background, lineWidth: 3))
    }

    // MARK: - Content

    @ViewBuilder
    private var content: some View {
        if let comment = item.comment {
            CommentRow(
                comment: comment,
                depth: 1,
                canReact: false,
                canReply: false,
                showTranslation: false,
                embedReplies: false,
                onReact: { _, _ in },
                onReply: { _ in },
                showsActions: false
            )
            .overlay(alignment: .topTrailing) {
                if let sanction { CommunitySanctionBadge(kind: sanction).padding(8) }
            }
            .padding(16)
            .background(theme.colors.surface, in: RoundedRectangle(cornerRadius: theme.radius.card))
        } else {
            PostCard(
                post: item.post,
                showTranslation: false,
                canReact: false,
                showViews: session.config.features.viewsEnabled,
                onTapPost: {},
                onReact: { _ in },
                onComment: {},
                showsActions: false,
                sanction: sanction
            )
            .allowsHitTesting(false)
        }
    }

    private var sanction: CommunitySanctionBadge.Kind? {
        switch item.status {
        case .removed: return .removed
        case .pending: return .hidden
        default: return nil
        }
    }

    // MARK: - Decisions

    /// Same pairs as the dashboard queue: a sanction already in place is
    /// confirmed or put back; live content is left or hidden.
    private var backButton: some View {
        let isSanctioned = sanction != nil
        return decisionButton(
            title: isSanctioned ? CommunityStrings.restore : CommunityStrings.leave,
            icon: isSanctioned ? .undoLeftRound : .check,
            iconColor: theme.colors.textTertiary,
            foreground: theme.colors.textPrimary,
            background: AnyShapeStyle(theme.colors.surface),
            bordered: true
        ) {
            onDecide(isSanctioned ? .restoreContent : .approve)
        }
    }

    private var confirmButton: some View {
        let removes = item.status == .removed
        let title: String
        switch item.status {
        case .removed: title = CommunityStrings.confirmRemove
        case .pending: title = CommunityStrings.confirmHide
        default: title = CommunityStrings.hide
        }
        return decisionButton(
            title: title,
            icon: removes ? .forbidden : .ghost,
            iconColor: .white,
            foreground: .white,
            background: AnyShapeStyle(removes ? AppwinCommunityPalette.alert : AppwinCommunityPalette.caution),
            bordered: false
        ) {
            onDecide(removes ? .removeContent : .hideContent)
        }
    }

    private func decisionButton(
        title: String,
        icon: CommunityIcon,
        iconColor: Color,
        foreground: Color,
        background: AnyShapeStyle,
        bordered: Bool,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            HStack(spacing: 4) {
                CommunityIconView(icon: icon, size: 12, color: iconColor)
                Text(title)
                    .font(theme.font(12, weight: .semibold))
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
            }
            .foregroundStyle(foreground)
            .padding(.horizontal, 12)
            .padding(.top, 8)
            .padding(.bottom, 7)
            .frame(maxWidth: .infinity)
            .background(background, in: RoundedRectangle(cornerRadius: 12))
            .overlay {
                if bordered {
                    RoundedRectangle(cornerRadius: 12).strokeBorder(theme.colors.border, lineWidth: 1)
                }
            }
        }
        .buttonStyle(.plain)
    }

    /// Categories that harm people read in red, the rest in amber (as on the dashboard).
    private static func isHarmful(_ category: String) -> Bool {
        ["harassment", "hate_speech", "sexual_content", "violence", "self_harm", "child_safety", "personal_data"]
            .contains(category)
    }
}
