// Reusable circular avatar: a remote image when `avatarURL` is set, with
// loading and failure both falling back to initials; otherwise a circle of
// initials (two letters, `?` when there is no name). Shared by the Home header
// and the messenger bubbles, which used to duplicate it.

import SwiftUI

struct AppwinAvatar: View {
    let name: String?
    var avatarURL: URL? = nil
    var size: CGFloat = 44
    /// Font for the initials. Defaults to `caption` for small bubble avatars;
    /// the header passes something larger.
    var font: Font? = nil
    /// Initials background, brand accent by default. Chat bubbles pass subtle.
    var fallbackFill: Color? = nil
    var fallbackForeground: Color? = nil

    @Environment(\.appwinTheme) private var theme

    var body: some View {
        Group {
            if let avatarURL {
                AsyncImage(url: avatarURL) { phase in
                    if let image = phase.image {
                        image.resizable().scaledToFill()   // image chargée
                    } else if phase.error != nil {
                        initialsCircle                     // échec → initiales
                    } else {
                        ProgressView()                     // en cours
                    }
                }
            } else {
                initialsCircle                             // pas d'URL → initiales
            }
        }
        .frame(width: size, height: size)
        .clipShape(Circle())
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

    /// First two letters of the name, uppercased. `?` when there is no name.
    private var initials: String {
        guard let name, !name.isEmpty else { return "?" }
        return String(name.prefix(2)).uppercased()
    }
}
