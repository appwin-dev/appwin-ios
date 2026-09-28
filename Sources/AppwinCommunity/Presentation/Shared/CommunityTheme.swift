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
    /// Inter, the mock's face - resolved by name, dropped when not bundled.
    var prefersInter = true
    var accentHex: String?
    /// Flat accent or two-stop gradient, a studio setting.
    var autoGradient = true
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
        /// Figma `post-card`, in device points; the studio moves it by notches.
        var card: CGFloat = 23
        var field: CGFloat = 16
        /// Figma post image - deliberately much squarer than the card.
        var small: CGFloat = 6
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
        autoGradient = config.theme.autoGradient
        fontScale = config.theme.fontScale.multiplier
        fontDesign = config.theme.fontFamily.design
        customFontName = config.theme.fontFamily == .custom ? config.theme.fontFamilyName : nil
        prefersInter = config.theme.fontFamily == .inter
        previewLineLimit = config.limits.feedPreviewLines

        let r = config.theme.radius.value
        radius.card = r
        radius.field = max(10, r - 8)
        // The post image keeps the mock's own small radius: it sits inside the
        // card, and a second big radius there reads as two nested bubbles.
        radius.small = 6
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
        if prefersInter, let name = Self.interPostScriptName(for: weight),
           UIFont(name: name, size: scaled) != nil {
            return .custom(name, size: scaled)
        }
        return .system(size: scaled, weight: weight, design: fontDesign)
    }

    /// Inter is only used when the host app actually ships it; there is no way
    /// to bundle a font into a Swift package binary that UIKit will resolve, so
    /// the system face stays the honest fallback rather than a broken render.
    private static func interPostScriptName(for weight: Font.Weight) -> String? {
        switch weight {
        case .bold, .heavy, .black: return "Inter-Bold"
        case .semibold: return "Inter-SemiBold"
        case .medium: return "Inter-Medium"
        default: return "Inter-Regular"
        }
    }

    /// Accent fill of the group pill - Figma gradient/brand/Fire at 115.525°.
    var accentFill: AnyShapeStyle { accentFill(degrees: 115.525) }

    /// Accent fill of the floating compose button - same stops, 124.717°.
    var composeFill: AnyShapeStyle { accentFill(degrees: 124.717) }

    /// Drop shadow under the compose button.
    ///
    /// The mock's shadow is the gradient's dark stop, not a fixed orange: a
    /// studio on a blue accent must not get an orange halo under its button.
    var accentShadow: Color {
        guard let accentHex, let dark = parseHexColor(shadeHex(accentHex)) else {
            return colors.accent.opacity(0.37)
        }
        return dark.opacity(0.37)
    }

    private func accentFill(degrees: Double) -> AnyShapeStyle {
        guard autoGradient, let accentHex, let dark = parseHexColor(shadeHex(accentHex)) else {
            return AnyShapeStyle(colors.accent)
        }
        // CSS angle: 0° = up, clockwise → vector (sin θ, −cos θ) in y-down space.
        let rad = degrees * .pi / 180
        let dx = sin(rad)
        let dy = -cos(rad)
        return AnyShapeStyle(
            LinearGradient(
                stops: [
                    .init(color: dark, location: 0.031),
                    .init(color: colors.accent, location: 0.711),
                ],
                startPoint: UnitPoint(x: 0.5 - dx / 2, y: 0.5 - dy / 2),
                endPoint: UnitPoint(x: 0.5 + dx / 2, y: 0.5 + dy / 2)
            )
        )
    }
}

// MARK: - Helpers couleur

/// Darker stop of the accent gradient.
///
/// Scaling the RGB channels drags the colour toward black and reads as
/// "colour to black"; here the hue is kept and only the HSL lightness and
/// saturation come down, so #FA7315 lands on the Figma Fire stop rather than a
/// muddy brown. Ratios read off that gradient: L x0.64, S x0.83.
func shadeHex(_ hex: String) -> String {
    guard let rgb = parseHexRGB(hex) else { return hex }
    let (h, s, l) = rgbToHSL(rgb)
    return hslToHex(h: h, s: min(1, max(0, s * 0.83)), l: min(1, max(0, l * 0.64)))
}

private func rgbToHSL(_ rgb: (r: Double, g: Double, b: Double)) -> (h: Double, s: Double, l: Double) {
    let maxV = Swift.max(rgb.r, rgb.g, rgb.b)
    let minV = Swift.min(rgb.r, rgb.g, rgb.b)
    let delta = maxV - minV
    let l = (maxV + minV) / 2
    guard delta > 0 else { return (0, 0, l) }

    let s = delta / (1 - abs(2 * l - 1))
    let h: Double
    if maxV == rgb.r {
        h = (rgb.g - rgb.b) / delta
    } else if maxV == rgb.g {
        h = (rgb.b - rgb.r) / delta + 2
    } else {
        h = (rgb.r - rgb.g) / delta + 4
    }
    return ((h * 60).truncatingRemainder(dividingBy: 360) + 360, s, l)
}

private func hslToHex(h: Double, s: Double, l: Double) -> String {
    let hue = h.truncatingRemainder(dividingBy: 360)
    let c = (1 - abs(2 * l - 1)) * s
    let x = c * (1 - abs((hue / 60).truncatingRemainder(dividingBy: 2) - 1))
    let m = l - c / 2

    let rgb: (Double, Double, Double)
    switch hue {
    case ..<60: rgb = (c, x, 0)
    case ..<120: rgb = (x, c, 0)
    case ..<180: rgb = (0, c, x)
    case ..<240: rgb = (0, x, c)
    case ..<300: rgb = (x, 0, c)
    default: rgb = (c, 0, x)
    }

    func byte(_ v: Double) -> Int { Int((Swift.max(0, Swift.min(1, v + m)) * 255).rounded()) }
    return String(format: "#%02X%02X%02X", byte(rgb.0), byte(rgb.1), byte(rgb.2))
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
