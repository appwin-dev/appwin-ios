import SwiftUI
import UIKit

/// A member's email and app user id under their name, for moderators and
/// admins (testimonials, support follow-up). The API sends them to no one else.
struct ProfileContactRows: View {
    let email: String?
    let externalId: String?

    var body: some View {
        VStack(spacing: 6) {
            if let email, !email.isEmpty {
                ProfileContactRow(label: CommunityStrings.profileEmail, value: email)
            }
            if let externalId, !externalId.isEmpty {
                ProfileContactRow(label: CommunityStrings.profileAppUserId, value: externalId)
            }
        }
        .padding(.horizontal, 20)
    }
}

private struct ProfileContactRow: View {
    let label: String
    let value: String

    @Environment(\.communityTheme) private var theme
    @State private var copied = false

    var body: some View {
        HStack(spacing: 6) {
            Text(label)
                .font(theme.font(12))
                .foregroundStyle(theme.colors.textTertiary)
            Text(value)
                .font(theme.font(12, weight: .medium))
                .foregroundStyle(theme.colors.textSecondary)
                .lineLimit(1)
                .truncationMode(.middle)
                .textSelection(.enabled)
            Button(action: copy) {
                if copied {
                    Text(CommunityStrings.copied)
                        .font(theme.font(12, weight: .semibold))
                        .foregroundStyle(theme.colors.accent)
                } else {
                    Image(systemName: "doc.on.doc")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(theme.colors.textTertiary)
                }
            }
            .buttonStyle(.plain)
            .frame(minWidth: 28, minHeight: 28)
            .accessibilityLabel(CommunityStrings.copyValue(label))
        }
    }

    private func copy() {
        UIPasteboard.general.string = value
        withAnimation(.easeOut(duration: 0.15)) { copied = true }
        Task {
            try? await Task.sleep(nanoseconds: 1_500_000_000)
            withAnimation(.easeOut(duration: 0.15)) { copied = false }
        }
    }
}
