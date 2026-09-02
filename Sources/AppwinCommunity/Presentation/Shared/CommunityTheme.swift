// Centralised styling, derived from the remote config.
//
// The theme is computed once at the top of the tree (`AppwinCommunityRootView`)
// and injected through the Environment. When the studio changes its accent
// colour, one re-render propagates the new theme to the whole screen.

import SwiftUI

struct CommunityTheme {
    var colors = Colors()
    var radius = Radius()
    var spacing = Spacing()
    /// Factor applied to every font size, a studio setting.
    var fontScale: CGFloat = 1
    var fontDesign: Font.Design = .default
    /// PostScript name of a font supplied by the host app, when there is one.
    var customFontName: String?
    var accentHex: String?
    /// Lines rendered before "see more" in the feed.
    var previewLineLimit: Int = 4

    struct Colors {
        var accent        = AppwinCommunityPalette.brand
        var onAccent      = AppwinCommunityPalette.onBrand
        var background    = AppwinCommunityPalette.background
        var surface       = AppwinCommunityPalette.surface
        var textPrimary   = AppwinCommunityPalette.textPrimary
        var textSecondary = AppwinCommunityPalette.textSecondary
        var textTertiary  = AppwinCommunityPalette.textTertiary
        var border        = AppwinCommunityPalette.border
        var danger        = AppwinCommunityPalette.danger
    }

    struct Radius {
        var card: CGFloat = 20
        var field: CGFloat = 16
        var small: CGFloat = 10
        var pill: CGFloat = 999
    }

    struct Spacing {
        let xs: CGFloat = 4
        let sm: CGFloat = 8
        let md: CGFloat = 12
        let lg: CGFloat = 16
        let xl: CGFloat = 24
        let xxl: CGFloat = 32
    }
}

// MARK: - Derivation from the config

extension CommunityTheme {
    init(config: CommunityConfig) {
        self = CommunityTheme()
        colors.accent = config.theme.primary
        colors.onAccent = config.theme.primaryForeground
        accentHex = config.theme.primaryHex
        fontScale = config.theme.fontScale.multiplier
        fontDesign = config.theme.fontFamily.design
        customFontName = config.theme.fontFamily == .custom ? config.theme.fontFamilyName : nil
        previewLineLimit = config.limits.feedPreviewLines

        let r = config.theme.radius.value
        radius.card = r
        radius.field = max(10, r - 4)
        radius.small = max(6, r / 2)
    }

    /// The theme's font at a given size.
    ///
    /// The font named by the studio is only applied if the host app really
    /// bundled it - `UIFont(name:)` returns `nil` otherwise, and we fall back
    /// silently to the system font. A missing font must not
    /// doit pas rendre le fil illisible.
    func font(_ size: CGFloat, weight: Font.Weight = .regular) -> Font {
        let scaled = size * fontScale
        if let customFontName, UIFont(name: customFontName, size: scaled) != nil {
            return .custom(customFontName, size: scaled)
        }
        return .system(size: scaled, weight: weight, design: fontDesign)
    }

    /// CTA gradient, matching the dashboard's `linear-gradient(155deg, …)`.
    var accentFill: AnyShapeStyle {
        guard let accentHex, let dark = parseHexColor(darkenHex(accentHex)) else {
            return AnyShapeStyle(colors.accent)
        }
        // CSS 155deg : 0° = haut, sens horaire → vecteur (sin θ, −cos θ) en y-down.
        let rad = 155.0 * .pi / 180
        let dx = sin(rad)
        let dy = -cos(rad)
        return AnyShapeStyle(
            LinearGradient(
                colors: [dark, colors.accent],
                startPoint: UnitPoint(x: 0.5 - dx / 2, y: 0.5 - dy / 2),
                endPoint: UnitPoint(x: 0.5 + dx / 2, y: 0.5 + dy / 2)
            )
        )
    }
}

// MARK: - Helpers couleur

func darkenHex(_ hex: String, amount: Double = 0.22) -> String {
    guard let rgb = parseHexRGB(hex) else { return hex }
    func clamp(_ n: Double) -> Int { Int(max(0, min(255, round(n * (1 - amount))))) }
    return String(
        format: "#%02X%02X%02X",
        clamp(rgb.r * 255),
        clamp(rgb.g * 255),
        clamp(rgb.b * 255)
    )
}

func parseHexRGB(_ raw: String) -> (r: Double, g: Double, b: Double)? {
    var hex = raw.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
    if hex.hasPrefix("#") { hex.removeFirst() }
    if hex.count == 3 { hex = hex.map { "\($0)\($0)" }.joined() }
    if hex.count == 8 { hex = String(hex.prefix(6)) }
    guard hex.count == 6, let v = UInt32(hex, radix: 16) else { return nil }
    return (
        Double((v >> 16) & 0xFF) / 255,
        Double((v >> 8) & 0xFF) / 255,
        Double(v & 0xFF) / 255
    )
}

func parseHexColor(_ hex: String) -> Color? {
    guard let rgb = parseHexRGB(hex) else { return nil }
    return Color(.sRGB, red: rgb.r, green: rgb.g, blue: rgb.b, opacity: 1)
}

// MARK: - Environment injection

private struct CommunityThemeKey: EnvironmentKey {
    static let defaultValue = CommunityTheme()
}

extension EnvironmentValues {
    var communityTheme: CommunityTheme {
        get { self[CommunityThemeKey.self] }
        set { self[CommunityThemeKey.self] = newValue }
    }
}

extension View {
    func communityTheme(_ theme: CommunityTheme) -> some View {
        environment(\.communityTheme, theme)
    }
}
