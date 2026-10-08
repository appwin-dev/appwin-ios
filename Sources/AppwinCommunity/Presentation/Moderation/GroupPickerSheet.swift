import SwiftUI

/// Figma « Choisir un groupe » (178:3909): moves a post to another group.
struct GroupPickerSheet: View {
    let groups: [CommunityGroup]
    let currentGroupId: String
    let onMove: (String) async throws -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var selection: String?
    @State private var isSending = false
    @State private var failed = false

    var body: some View {
        CommunitySheetScaffold(title: CommunityStrings.chooseGroupTitle) {
            CommunityActionPill(
                title: CommunityStrings.moveAction,
                isEnabled: selection != nil && selection != currentGroupId,
                isLoading: isSending,
                action: move
            )
        } content: {
            CommunityCheckList(
                options: groups.map(\.id),
                selection: $selection,
                title: { id in
                    let group = groups.first { $0.id == id }
                    return [group?.emoji, group?.name].compactMap { $0 }.joined(separator: " ")
                }
            )
            if failed { CommunityErrorLine() }
        }
        .onAppear { selection = currentGroupId }
    }

    private func move() {
        guard let selection else { return }
        isSending = true
        failed = false
        Task {
            do {
                try await onMove(selection)
                dismiss()
            } catch {
                failed = true
            }
            isSending = false
        }
    }
}
