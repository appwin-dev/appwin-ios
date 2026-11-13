import SwiftUI

/// Figma « Avertissement » (178:3803), « Shadow-Ban » (200:4345) and « Bannir »
/// (200:4370): a sanction on a member, with its message or motif.
struct MemberSanctionSheet: View {
    enum Kind {
        case warn, shadowBan, ban

        var action: ModerationAction {
            switch self {
            case .warn: return .warn
            case .shadowBan: return .shadowBan
            case .ban: return .ban
            }
        }
    }

    let kind: Kind
    let member: CommunityAuthor

    @Environment(\.dismiss) private var dismiss
    @State private var duration: SanctionDuration = .permanent
    @State private var text = ""
    @State private var isSending = false
    @State private var failed = false

    private var trimmed: String { text.trimmingCharacters(in: .whitespacesAndNewlines) }

    var body: some View {
        CommunitySheetScaffold(title: title) {
            CommunityActionPill(
                title: kind == .warn ? CommunityStrings.send : CommunityStrings.validate,
                tone: kind == .ban ? .alert : .caution,
                // A warning without a message says nothing.
                isEnabled: kind != .warn || !trimmed.isEmpty,
                isLoading: isSending,
                action: send
            )
        } content: {
            CommunityInfoBox(markdown: info)
            CommunityMemberHeader(nickname: member.nickname, avatarUrl: member.avatarUrl)
            VStack(alignment: .leading, spacing: 16) {
                if kind != .warn {
                    CommunitySelectField(
                        label: CommunityStrings.chooseDuration,
                        options: SanctionDuration.allCases,
                        selection: $duration,
                        title: CommunityStrings.duration
                    )
                }
                CommunityTextArea(
                    label: kind == .warn ? CommunityStrings.message : CommunityStrings.motive,
                    text: $text,
                    placeholder: kind == .shadowBan
                        ? CommunityStrings.teamOnlyPlaceholder
                        : CommunityStrings.visibleBy(member.nickname)
                )
            }
            if failed { CommunityErrorLine() }
        }
    }

    private var title: String {
        switch kind {
        case .warn: return CommunityStrings.warnTitle
        case .shadowBan: return CommunityStrings.shadowBanTitle
        case .ban: return CommunityStrings.banTitle
        }
    }

    private var info: String {
        switch kind {
        case .warn: return CommunityStrings.warnInfo(member.nickname)
        case .shadowBan: return CommunityStrings.shadowBanInfo(member.nickname)
        case .ban: return CommunityStrings.banInfo(member.nickname)
        }
    }

    private func send() {
        isSending = true
        failed = false
        Task {
            do {
                try await Factory.moderationRepository().decide(
                    targetType: .profile,
                    targetId: member.id,
                    action: kind.action,
                    reason: trimmed.isEmpty ? nil : trimmed,
                    durationHours: kind == .warn ? nil : duration.hours,
                    reportIds: []
                )
                dismiss()
            } catch {
                failed = true
            }
            isSending = false
        }
    }
}
