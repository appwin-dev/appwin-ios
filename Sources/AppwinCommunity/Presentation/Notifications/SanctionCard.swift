import SwiftUI

/// Figma « Notification » (174:1396): one sanction, what happened above, the
/// card with its label and « J'ai compris ». Shown at the top of the inbox
/// until acknowledged.
struct SanctionCard: View {
    let sanction: CommunityNotification
    let teamName: String
    let author: CommunityProfile
    let onUnderstood: () -> Void

    @Environment(\.communityTheme) private var theme
    @Environment(\.locale) private var locale

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text(headline)
                .font(theme.font(16, weight: .semibold))
                .foregroundStyle(theme.colors.textPrimary)
                .fixedSize(horizontal: false, vertical: true)
            VStack(alignment: .leading, spacing: 0) {
                content.padding(12)
                Rectangle().fill(theme.colors.raised).frame(height: 1)
                HStack(spacing: 8) {
                    HStack(spacing: 4) {
                        CommunityIconView(icon: labelIcon, size: 14, color: labelColor)
                        Text(label)
                            .font(theme.font(14, weight: .medium))
                            .foregroundStyle(labelColor)
                            .lineLimit(2)
                    }
                    Spacer(minLength: 8)
                    CommunityActionPill(title: CommunityStrings.understood, tone: .invert, action: onUnderstood)
                }
                .padding(12)
            }
            .background(theme.colors.surface, in: RoundedRectangle(cornerRadius: 16))
            .overlay(RoundedRectangle(cornerRadius: 16).strokeBorder(theme.colors.raised, lineWidth: 1))
        }
    }

    private var headline: String {
        switch sanction.type {
        case .accountWarned:
            return CommunityStrings.warnSection(teamName)
        case .accountBanned:
            return sanction.sanctionUntil == nil ? CommunityStrings.banSection : CommunityStrings.tempBanSection
        default:
            return sanction.targetType == "comment"
                ? CommunityStrings.commentRemovedSection
                : CommunityStrings.postRemovedSection
        }
    }

    @ViewBuilder
    private var content: some View {
        switch sanction.type {
        case .contentRemoved:
            VStack(alignment: .leading, spacing: 12) {
                HStack(spacing: 8) {
                    CommunityAvatar(url: author.avatarUrl, nickname: author.nickname, size: 24)
                    Text(author.nickname)
                        .font(theme.font(14, weight: .semibold))
                        .foregroundStyle(theme.colors.textPrimary)
                    CommunityRelativeDate(date: sanction.createdAt, size: 10)
                }
                if let excerpt = sanction.excerpt, !excerpt.isEmpty {
                    bodyText(excerpt)
                }
            }
        case .accountBanned:
            bodyText(message ?? CommunityStrings.banDefaultBody)
        default:
            bodyText(message ?? "")
        }
    }

    /// The moderator's own words; a reason key is shown as the label instead.
    private var message: String? {
        guard let reason = sanction.reason?.trimmingCharacters(in: .whitespacesAndNewlines),
              !reason.isEmpty,
              CommunityStrings.reasonLabel(reason) == reason
        else { return nil }
        return reason
    }

    private func bodyText(_ text: String) -> some View {
        Text(text)
            .font(theme.font(14))
            .foregroundStyle(theme.colors.textPrimary)
            .frame(maxWidth: .infinity, alignment: .leading)
            .fixedSize(horizontal: false, vertical: true)
    }

    private var label: String {
        switch sanction.type {
        case .accountWarned:
            return CommunityStrings.warnTitle
        case .accountBanned:
            guard let until = sanction.sanctionUntil else { return CommunityStrings.permanentBanLabel }
            return CommunityStrings.tempBanLabel(
                until.formatted(.dateTime.day().month(.abbreviated).hour().minute().locale(locale))
            )
        default:
            guard let reason = sanction.reason, !reason.isEmpty else {
                return CommunityStrings.removedFallbackReason
            }
            return message == nil ? CommunityStrings.reasonLabel(reason) : CommunityStrings.removedFallbackReason
        }
    }

    private var labelIcon: CommunityIcon {
        sanction.type == .accountWarned ? .dangerTriangle : .forbidden
    }

    private var labelColor: Color {
        sanction.type == .accountWarned ? AppwinCommunityPalette.caution : AppwinCommunityPalette.alert
    }
}
