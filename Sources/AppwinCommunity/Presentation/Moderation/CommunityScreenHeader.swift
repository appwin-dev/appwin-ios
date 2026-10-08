import SwiftUI

/// Figma header of a pushed screen (182:857, 174:1396): a round back button and
/// the title centred.
struct CommunityScreenHeader: View {
    let title: String
    let onBack: () -> Void

    @Environment(\.communityTheme) private var theme

    var body: some View {
        ZStack {
            Text(title)
                .font(theme.font(16, weight: .medium))
                .foregroundStyle(theme.colors.textPrimary)
                .lineLimit(1)
                .padding(.horizontal, 64)
            HStack {
                CommunityGlassButton(
                    systemImage: "chevron.left",
                    accessibilityLabel: CommunityStrings.back,
                    action: onBack
                )
                Spacer(minLength: 0)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
    }
}
