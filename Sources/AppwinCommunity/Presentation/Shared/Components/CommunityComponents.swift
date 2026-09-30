import SwiftUI
import UIKit
import AppwinCore

// UI building blocks shared by the feed, the detail screen and the profile.

/// In-memory avatar cache keyed by URL.
///
/// SwiftUI `AsyncImage` re-downloads on every remount, so scrolling a feed of
/// the same authors flashes initials then the photo over and over. Same
/// pattern as `AppwinAvatarImageCache` in Support.
@MainActor
enum CommunityAvatarImageCache {
    private static let cache = NSCache<NSString, UIImage>()

    static func image(for url: URL) -> UIImage? {
        cache.object(forKey: url.absoluteString as NSString)
    }

    static func store(_ image: UIImage, for url: URL) {
        cache.setObject(image, forKey: url.absoluteString as NSString)
    }
}

/// A member's avatar. Loads the image when there is one and falls back to
/// initials otherwise - a feed without avatars stays readable, a feed of grey
/// squares does not.
struct CommunityAvatar: View {
    let url: URL?
    let nickname: String
    var size: CGFloat = 40

    @Environment(\.communityTheme) private var theme
    @State private var loadedImage: UIImage?

    var body: some View {
        Group {
            if let loadedImage {
                Image(uiImage: loadedImage)
                    .resizable()
                    .scaledToFill()
            } else {
                // Keep the disc stable while the first download runs - never a
                // spinner that would flash again on every feed redraw.
                initials
            }
        }
        .frame(width: size, height: size)
        .clipShape(Circle())
        .task(id: url?.absoluteString) {
            await loadImage()
        }
    }

    @MainActor
    private func loadImage() async {
        guard let url else {
            loadedImage = nil
            return
        }
        if let cached = CommunityAvatarImageCache.image(for: url) {
            loadedImage = cached
            return
        }
        guard
            let (data, response) = try? await URLSession.shared.data(from: url),
            let http = response as? HTTPURLResponse,
            (200..<300).contains(http.statusCode),
            let image = UIImage(data: data)
        else {
            loadedImage = nil
            return
        }
        CommunityAvatarImageCache.store(image, for: url)
        loadedImage = image
    }

    /// Figma Profile avatar: the brand at 24 % over bg/container (its
    /// "Ellipse 920"), and the initials drawn twice in place, brand at 16 %
    /// under text/main at 12 %. Same as the dashboard preview.
    private var initials: some View {
        ZStack {
            theme.colors.surface
            theme.colors.accent.opacity(0.24)
            Text(initialsText)
                .foregroundStyle(theme.colors.accent.opacity(0.16))
            Text(initialsText)
                .foregroundStyle(theme.colors.textPrimary.opacity(0.12))
        }
        .font(theme.font(size * 0.4, weight: .heavy))
    }

    private var initialsText: String {
        let parts = nickname.split(separator: " ").prefix(2)
        let letters = parts.compactMap { $0.first }.map(String.init).joined()
        return letters.isEmpty ? "?" : letters.uppercased()
    }
}

/// Team chip next to a studio member's nickname. `compact` is the comment
/// variant: tighter, on bg/medium since it sits in a bg/low bubble.
struct CommunityTeamBadge: View {
    var compact = false

    @Environment(\.communityTheme) private var theme

    var body: some View {
        Text(CommunityStrings.teamBadge)
            .font(theme.font(10, weight: .bold))
            .foregroundStyle(theme.colors.textTertiary)
            .padding(.horizontal, 6)
            .padding(.vertical, compact ? 2 : 4)
            .background(compact ? theme.colors.border : theme.colors.raised, in: Capsule())
    }
}

/// Figma post action: a 20pt glyph and its count, 64pt wide so the row does
/// not jump when a count grows.
struct CommunityCountAction: View {
    let icon: CommunityIcon
    let count: Int
    var tint: Color?
    var accessibilityLabel: String
    let action: () -> Void

    @Environment(\.communityTheme) private var theme

    var body: some View {
        Button(action: action) {
            HStack(spacing: 4) {
                CommunityIconView(icon: icon, size: 20, color: tint ?? theme.colors.textTertiary)
                Text("\(count)")
                    .font(theme.font(12, weight: .medium))
                    .foregroundStyle(theme.colors.textTertiary)
            }
            .frame(minWidth: 64, minHeight: 32, alignment: .leading)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(accessibilityLabel)
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
///
/// Set `expandsToFill` when the state replaces the whole feed (load error,
/// product off): it then occupies the remaining height under the header
/// instead of collapsing into a short island in the middle of the screen.
struct CommunityEmptyState: View {
    var systemImage: String = ""
    /// Solar icon of the Figma frame; wins over `systemImage` when set.
    var icon: CommunityIcon?
    let title: String
    var message: String?
    var actionTitle: String?
    var expandsToFill: Bool = false
    var action: (() -> Void)?

    @Environment(\.communityTheme) private var theme

    var body: some View {
        VStack(spacing: 16) {
            if expandsToFill { Spacer(minLength: 0) }

            if let icon {
                CommunityIconView(icon: icon, size: 32, color: theme.colors.textTertiary)
            } else {
                Image(systemName: systemImage)
                    .font(.system(size: 28, weight: .regular))
                    .foregroundStyle(theme.colors.textTertiary.opacity(0.6))
            }
            VStack(spacing: 4) {
                Text(title)
                    .font(theme.font(14, weight: .medium))
                    .foregroundStyle(theme.colors.textPrimary)
                    .multilineTextAlignment(.center)
                if let message {
                    Text(message)
                        .font(theme.font(14, weight: .medium))
                        .foregroundStyle(theme.colors.textTertiary)
                        .multilineTextAlignment(.center)
                }
            }
            if let actionTitle, let action {
                CommunityPrimaryButton(title: actionTitle, action: action)
                    .padding(.top, theme.spacing.sm)
            }

            if expandsToFill { Spacer(minLength: 0) }
        }
        .frame(maxWidth: .infinity, maxHeight: expandsToFill ? .infinity : nil)
        .padding(theme.spacing.xl)
    }
}

/// Short relative date ("2h", "maintenant"), in the device's language.
///
/// `RelativeDateTimeFormatter` with `.short` emits "il y a 0 s" / "0s ago" for a
/// post just published - readable but ugly. Under a minute we force a stable
/// "now" label instead.
struct CommunityRelativeDate: View {
    let date: Date
    var size: CGFloat = 12

    @Environment(\.communityTheme) private var theme

    private static func formatter() -> RelativeDateTimeFormatter {
        let f = RelativeDateTimeFormatter()
        f.unitsStyle = .short
        f.locale = AppwinDisplayLocale.locale(languageCode: nil)
        return f
    }

    var body: some View {
        Text(label)
            .font(theme.font(size, weight: .medium))
            .foregroundStyle(theme.colors.textTertiary)
    }

    private var label: String {
        let seconds = abs(date.timeIntervalSinceNow)
        if seconds < 60 {
            return CommunityStrings.relativeNow
        }
        return Self.formatter().localizedString(for: date, relativeTo: Date())
    }
}
