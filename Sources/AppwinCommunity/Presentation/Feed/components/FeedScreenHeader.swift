import SwiftUI

/// Screens the feed header opens over the feed.
enum FeedScreen: String, Identifiable {
    case moderation, sanctions

    var id: String { rawValue }
}

/// Screen header - Figma feed 5:1837: large title and the member's avatar,
/// the group pills under them, on the page colour with a soft drop shadow
/// the list scrolls under. The close button only shows when presented.
///
/// Moderators get the flag to their queue (178:2735); a member with unread
/// sanctions gets the bell (178:3385), which disappears once they are read.
struct FeedScreenHeader: View {
    let showsCloseButton: Bool
    let onClose: () -> Void
    let onOpenProfile: () -> Void
    let onOpen: (FeedScreen) -> Void

    @EnvironmentObject private var session: CommunitySession
    @Environment(\.communityTheme) private var theme

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 12) {
                if let headerTitle {
                    Text(headerTitle)
                        .font(theme.font(32, weight: .medium))
                        .foregroundStyle(theme.colors.textPrimary)
                        .lineLimit(1)
                        .minimumScaleFactor(0.7)
                        .frame(maxWidth: .infinity, alignment: .leading)
                } else {
                    Spacer(minLength: 0)
                }

                if showsCloseButton {
                    CommunityGlassButton(
                        systemImage: "xmark",
                        accessibilityLabel: CommunityStrings.close,
                        action: onClose
                    )
                }

                if session.unreadSanctionCount > 0 {
                    badgedIcon(.bell, count: session.unreadSanctionCount, label: CommunityStrings.openSanctions) {
                        onOpen(.sanctions)
                    }
                }

                if session.profile.canModerate {
                    badgedIcon(.flag, count: session.moderationPendingCount, label: CommunityStrings.openModeration) {
                        onOpen(.moderation)
                    }
                }

                Button(action: onOpenProfile) {
                    CommunityAvatar(
                        url: session.profile.avatarUrl,
                        nickname: session.profile.nickname,
                        size: 40
                    )
                }
                .buttonStyle(.plain)
            }
            .frame(minHeight: 40)
            .padding(.horizontal, 20)
            .padding(.top, 16)

            if session.isReady, session.config.features.enabled, session.groups.count > 1 {
                GroupTabBar()
            } else {
                Color.clear.frame(height: 16)
            }
        }
        .background(alignment: .topLeading) {
            theme.colors.background
                .overlay(alignment: .topLeading) { CommunityAccentGlow() }
                .clipped()
                .ignoresSafeArea(edges: .top)
        }
        .compositingGroup()
        .shadow(color: .black.opacity(0.08), radius: 10, y: 12)
    }

    private func badgedIcon(
        _ icon: CommunityIcon,
        count: Int,
        label: String,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            CommunityIconView(icon: icon, size: 24, color: theme.colors.textPrimary)
                .frame(width: 32, height: 40)
                .overlay(alignment: .topTrailing) {
                    if count > 0 {
                        CommunityCountBadge(count: count).offset(x: 4, y: 2)
                    }
                }
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(label)
    }

    /// The studio's title, or none: an empty title is a choice, and the
    /// project name the SDK used to fall back on is not always what the host
    /// app wants on screen.
    private var headerTitle: String? {
        guard session.config.theme.headerTitleVisible,
              let custom = session.config.theme.headerTitle?.trimmingCharacters(in: .whitespacesAndNewlines),
              !custom.isEmpty
        else { return nil }
        return custom
    }
}
