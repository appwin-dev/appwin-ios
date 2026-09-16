import SwiftUI

// UI building blocks shared by the feed, the detail screen and the profile.

/// A member's avatar. Loads the image when there is one and falls back to
/// initials otherwise - a feed without avatars stays readable, a feed of grey
/// squares does not.
struct CommunityAvatar: View {
    let url: URL?
    let nickname: String
    var size: CGFloat = 40

    @Environment(\.communityTheme) private var theme

    var body: some View {
        Group {
            if let url {
                AsyncImage(url: url) { phase in
                    switch phase {
                    case .success(let image):
                        image.resizable().scaledToFill()
                    default:
                        initials
                    }
                }
            } else {
                initials
            }
        }
        .frame(width: size, height: size)
        .clipShape(Circle())
    }

    private var initials: some View {
        ZStack {
            theme.colors.accent.opacity(0.15)
            Text(initialsText)
                .font(theme.font(size * 0.36, weight: .semibold))
                .foregroundStyle(theme.colors.accent)
        }
    }

    private var initialsText: String {
        let parts = nickname.split(separator: " ").prefix(2)
        let letters = parts.compactMap { $0.first }.map(String.init).joined()
        return letters.isEmpty ? "?" : letters.uppercased()
    }
}

/// Team badge shown under a studio member's nickname.
struct CommunityTeamBadge: View {
    @Environment(\.communityTheme) private var theme

    var body: some View {
        Text(CommunityStrings.teamBadge)
            .font(theme.font(10, weight: .semibold))
            .foregroundStyle(theme.colors.onAccent)
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(theme.colors.accent, in: Capsule())
    }
}

/// Action button under a post (like, comment, share).
struct CommunityActionButton: View {
    let systemImage: String
    let label: String
    var isActive = false
    let action: () -> Void

    @Environment(\.communityTheme) private var theme

    var body: some View {
        Button(action: action) {
            HStack(spacing: 6) {
                Image(systemName: systemImage)
                    .font(.system(size: 16, weight: .medium))
                Text(label)
                    .font(theme.font(14, weight: .medium))
            }
            .foregroundStyle(isActive ? theme.colors.accent : theme.colors.textTertiary)
            // No side padding: the row spaces the buttons itself (Figma
            // `card-actions`, 24pt). The hit area is kept by the min height.
            .frame(minHeight: 32)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

/// Primary CTA (post, send). Carries the theme's gradient.
struct CommunityPrimaryButton: View {
    let title: String
    var systemImage: String?
    var isEnabled = true
    var isLoading = false
    let action: () -> Void

    @Environment(\.communityTheme) private var theme

    var body: some View {
        Button(action: action) {
            HStack(spacing: 8) {
                if isLoading {
                    ProgressView()
                        .progressViewStyle(.circular)
                        .tint(theme.colors.onAccent)
                } else if let systemImage {
                    Image(systemName: systemImage)
                        .font(.system(size: 15, weight: .semibold))
                }
                Text(title)
                    .font(theme.font(15, weight: .semibold))
            }
            .foregroundStyle(theme.colors.onAccent)
            .padding(.horizontal, 18)
            .padding(.vertical, 12)
            .background(theme.accentFill, in: Capsule())
            .opacity(isEnabled && !isLoading ? 1 : 0.5)
        }
        .buttonStyle(.plain)
        .disabled(!isEnabled || isLoading)
    }
}

/// Generic empty state. Serves both the postless feed and the disabled
/// community - two screens too alike to write twice.
struct CommunityEmptyState: View {
    let systemImage: String
    let title: String
    var message: String?
    var actionTitle: String?
    var action: (() -> Void)?

    @Environment(\.communityTheme) private var theme

    var body: some View {
        VStack(spacing: theme.spacing.md) {
            Image(systemName: systemImage)
                .font(.system(size: 36, weight: .light))
                .foregroundStyle(theme.colors.textTertiary)
            Text(title)
                .font(theme.font(16, weight: .semibold))
                .foregroundStyle(theme.colors.textPrimary)
                .multilineTextAlignment(.center)
            if let message {
                Text(message)
                    .font(theme.font(14))
                    .foregroundStyle(theme.colors.textTertiary)
                    .multilineTextAlignment(.center)
            }
            if let actionTitle, let action {
                CommunityPrimaryButton(title: actionTitle, action: action)
                    .padding(.top, theme.spacing.sm)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(theme.spacing.xl)
    }
}

/// Short relative date ("2h ago"), in the device's language.
struct CommunityRelativeDate: View {
    let date: Date

    @Environment(\.communityTheme) private var theme

    private static let formatter: RelativeDateTimeFormatter = {
        let f = RelativeDateTimeFormatter()
        f.unitsStyle = .short
        return f
    }()

    var body: some View {
        Text(Self.formatter.localizedString(for: date, relativeTo: Date()))
            .font(theme.font(12))
            .foregroundStyle(theme.colors.textTertiary)
    }
}
