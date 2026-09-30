// The typographic scale: a closed set of styles (h1 to h4, body L/M/S, caption)
// rather than `.font(.system(size:))` scattered around. Change one style and
// every screen follows.
//
// The SDK embeds no font, so it uses the system font. To wire a custom one
// later, fill in `displayFontName` / `bodyFontName` after adding it to the
// package resources.

import SwiftUI

/// Available styles. `display*` are titles, `body*` is running text.
enum AppwinTextStyle {
    case displayXL   // 32 - gros titre d'accueil
    case displayL    // 28
    case title       // 22 - titre d'écran / header
    case headline    // 18 - sous-titre, libellé fort
    case bodyL       // 18
    case bodyM       // 16 - corps par défaut
    case bodyS       // 14
    case caption     // 12 - légendes, métadonnées
}

enum AppwinTypography {

    // Set a custom font here; nil means the system font.
    static let displayFontName: String? = nil
    static let bodyFontName: String? = nil

    /// The SwiftUI `Font` for a given style.
    static func font(_ style: AppwinTextStyle) -> Font {
        let spec = spec(for: style)
        if let name = customFontName(for: style) {
            return .custom(name, size: spec.size).weight(spec.weight)
        }
        return .system(size: spec.size, weight: spec.weight)
    }

    // MARK: - Size and weight table

    private static func spec(for style: AppwinTextStyle) -> (size: CGFloat, weight: Font.Weight) {
        switch style {
        case .displayXL: return (32, .black)
        case .displayL:  return (28, .black)
        case .title:     return (22, .bold)
        case .headline:  return (18, .semibold)
        case .bodyL:     return (18, .regular)
        case .bodyM:     return (16, .regular)
        case .bodyS:     return (14, .regular)
        case .caption:   return (12, .semibold)
        }
    }

    private static func customFontName(for style: AppwinTextStyle) -> String? {
        switch style {
        case .displayXL, .displayL, .title: return displayFontName
        default:                            return bodyFontName
        }
    }
}

// MARK: - Sugar

extension View {
    /// `Text("Hello").appwinText(.title)` applies font and colour at once.
    func appwinText(_ style: AppwinTextStyle, color: Color = AppwinTokens.textHigh) -> some View {
        self.font(AppwinTypography.font(style))
            .foregroundColor(color)
    }
}
