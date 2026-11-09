import SwiftUI

/// Figma « Choisir un motif » (178:3480 delete, 178:3559 hide): the motif goes
/// with the decision, and the author is told it.
struct ModerationReasonSheet: View {
    enum Kind { case hide, remove }

    let kind: Kind
    let authorName: String
    let onConfirm: (ModerationReason) async throws -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var reason: ModerationReason?
    @State private var isSending = false
    @State private var failed = false

    var body: some View {
        CommunitySheetScaffold(title: CommunityStrings.chooseReason) {
            CommunityActionPill(
                title: kind == .remove ? CommunityStrings.delete : CommunityStrings.hide,
                tone: kind == .remove ? .alert : .caution,
                isEnabled: reason != nil,
                isLoading: isSending,
                action: confirm
            )
        } content: {
            CommunityInfoBox(
                markdown: kind == .remove
                    ? CommunityStrings.removeInfo(authorName)
                    : CommunityStrings.hideInfo(authorName)
            )
            CommunityCheckList(
                options: ModerationReason.allCases,
                selection: $reason,
                title: CommunityStrings.moderationReason
            )
            if failed { CommunityErrorLine() }
        }
    }

    private func confirm() {
        guard let reason else { return }
        isSending = true
        failed = false
        Task {
            do {
                try await onConfirm(reason)
                dismiss()
            } catch {
                failed = true
            }
            isSending = false
        }
    }
}
