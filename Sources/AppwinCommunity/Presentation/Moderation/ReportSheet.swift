import SwiftUI

/// What a member reports: a post, a comment or a profile.
struct ReportTarget: Identifiable {
    let type: String
    let targetId: String

    var id: String { "\(type):\(targetId)" }

    init(type: String, id: String) {
        self.type = type
        self.targetId = id
    }
}

/// Figma « Signaler » (155:1259): one reason from the list, sent at once.
struct ReportSheet: View {
    let target: ReportTarget

    @Environment(\.communityTheme) private var theme
    @Environment(\.dismiss) private var dismiss
    @State private var reason: CommunityReportReason?
    @State private var isSending = false
    @State private var isSent = false
    @State private var failed = false

    var body: some View {
        CommunitySheetScaffold(title: CommunityStrings.reportSheetTitle) {
            if !isSent {
                CommunityActionPill(
                    title: CommunityStrings.validate,
                    tone: .alert,
                    isEnabled: reason != nil,
                    isLoading: isSending,
                    action: submit
                )
            }
        } content: {
            if isSent {
                Text(CommunityStrings.reportSent)
                    .font(theme.font(16, weight: .medium))
                    .foregroundStyle(theme.colors.textPrimary)
            } else {
                Text(CommunityStrings.reportQuestion)
                    .font(theme.font(16, weight: .medium))
                    .foregroundStyle(theme.colors.textPrimary)
                CommunityCheckList(
                    options: CommunityReportReason.allCases,
                    selection: $reason,
                    title: CommunityStrings.reportReason
                )
                if failed { CommunityErrorLine() }
            }
        }
    }

    private func submit() {
        guard let reason else { return }
        isSending = true
        failed = false
        Task {
            do {
                try await Factory.repository().report(
                    targetType: target.type,
                    targetId: target.targetId,
                    reason: reason,
                    note: nil
                )
                isSent = true
                try? await Task.sleep(nanoseconds: 1_200_000_000)
                dismiss()
            } catch {
                failed = true
            }
            isSending = false
        }
    }
}
