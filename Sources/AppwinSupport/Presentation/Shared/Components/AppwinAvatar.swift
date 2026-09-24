// Reusable circular avatar: a remote image when `avatarURL` is set, with
// loading and failure both falling back; otherwise the chosen fallback.
// Shared by the Home header and the messenger bubbles.
//
// Images are cached in memory by URL so realtime message inserts do not
// flash a ProgressView on every agent bubble remount (AsyncImage does).

import SwiftUI
import UIKit

@MainActor
enum AppwinAvatarImageCache {
    private static let cache = NSCache<NSString, UIImage>()

    static func image(for url: URL) -> UIImage? {
        cache.object(forKey: url.absoluteString as NSString)
    }

    static func store(_ image: UIImage, for url: URL) {
        cache.setObject(image, forKey: url.absoluteString as NSString)
    }
}

struct AppwinAvatar: View {
    /// Matches dashboard `ProjectAvatar` when the project has no logo: Lucide
    /// `Package` on `#6366f1` (see `project-avatar.tsx`).
    enum FallbackStyle {
        /// Two-letter initials (customer side).
        case initials
        /// Studio / agent default: package glyph on indigo.
        case project
    }

    let name: String?
    var avatarURL: URL? = nil
    var size: CGFloat = 44
    /// Font for the initials. Defaults to `caption` for small bubble avatars;
    /// the header passes something larger.
    var font: Font? = nil
    /// Background for the fallback disc. Defaults depend on ``fallbackStyle``.
    var fallbackFill: Color? = nil
    var fallbackForeground: Color? = nil
    var fallbackStyle: FallbackStyle = .initials

    /// Dashboard default when `project.color` is unset (`ProjectAvatar`).
    private static let projectFallbackFill = Color(hex: 0x6366F1)

    @Environment(\.appwinTheme) private var theme
    @State private var loadedImage: UIImage?

    var body: some View {
        Group {
            if let loadedImage {
                Image(uiImage: loadedImage)
                    .resizable()
                    .scaledToFill()
            } else if avatarURL != nil {
                // Keep the disc stable while the first download runs - never a
                // spinner that would flash again on every thread redraw.
                fallbackContent
            } else {
                fallbackContent
            }
        }
        .frame(width: size, height: size)
        .clipShape(Circle())
        .task(id: avatarURL?.absoluteString) {
            await loadImage()
        }
    }

    @MainActor
    private func loadImage() async {
        guard let avatarURL else {
            loadedImage = nil
            return
        }
        if let cached = AppwinAvatarImageCache.image(for: avatarURL) {
            loadedImage = cached
            return
        }
        guard
            let (data, response) = try? await URLSession.shared.data(from: avatarURL),
            let http = response as? HTTPURLResponse,
            (200..<300).contains(http.statusCode),
            let image = UIImage(data: data)
        else {
            loadedImage = nil
            return
        }
        AppwinAvatarImageCache.store(image, for: avatarURL)
        loadedImage = image
    }

    @ViewBuilder
    private var fallbackContent: some View {
        switch fallbackStyle {
        case .initials:
            initialsCircle
        case .project:
            projectPackageCircle
        }
    }

    private var initialsCircle: some View {
        Circle()
            .fill(fallbackFill ?? theme.colors.accent)
            .overlay(
                Text(initials)
                    .font(font ?? theme.fonts.caption)
                    .foregroundColor(fallbackForeground ?? theme.colors.onAccent)
            )
    }

    /// Same silhouette as the dashboard's type=`other` ProjectAvatar (Package).
    private var projectPackageCircle: some View {
        Circle()
            .fill(fallbackFill ?? Self.projectFallbackFill)
            .overlay(
                Image(systemName: "shippingbox.fill")
                    .font(.system(size: size * 0.48, weight: .medium))
                    .foregroundColor(fallbackForeground ?? .white)
            )
    }

    /// First two letters of the name, uppercased. `?` when there is no name.
    private var initials: String {
        guard let name, !name.isEmpty else { return "?" }
        return String(name.prefix(2)).uppercased()
    }
}
