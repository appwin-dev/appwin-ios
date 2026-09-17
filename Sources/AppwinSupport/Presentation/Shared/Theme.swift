// Centralised styling, the equivalent of Intercom's config object.

import SwiftUI

struct AppwinTheme {
    var colors = Colors()
    var fonts = Fonts()
    var radius = Radius()
    var spacing = Spacing()
    var design = MessengerDesign.defaults
    var accentHex: String?

    struct Colors {
        var accent        = AppwinTokens.accent
        var background    = AppwinTokens.surface
        var surface       = AppwinTokens.surfaceMuted
        var textPrimary   = AppwinTokens.textHigh
        var textSecondary = AppwinTokens.textMedium
        var textTertiary  = AppwinTokens.textLow
        var onAccent      = AppwinTokens.textOnBrand
        var border        = AppwinTokens.border
    }

    struct Fonts {
        var title    = AppwinTypography.font(.title)
        var headline = AppwinTypography.font(.headline)
        var body     = AppwinTypography.font(.bodyM)
        var caption  = AppwinTypography.font(.caption)
    }

    struct Radius {
        var sheet: CGFloat = 24
        var card:  CGFloat = 16
        var field: CGFloat = 20
        var small: CGFloat = 8
    }

    struct Spacing {
        let xs: CGFloat  = 4
        let sm: CGFloat  = 8
        let md: CGFloat  = 12
        let lg: CGFloat  = 16
        let xl: CGFloat  = 24
        let xxl: CGFloat = 32
    }
}

// MARK: - Theme derived from the remote config

extension AppwinTheme {
    init(config: MessengerConfig) {
        self = AppwinTheme()
        colors.accent = config.branding.accent
        colors.onAccent = config.branding.onAccent
        accentHex = config.branding.accentHex
        design = config.design
        radius.card = config.design.radius.value
        radius.field = max(12, config.design.radius.value - 4)
        radius.small = max(6, config.design.radius.value / 2)
    }

    /// CTA gradient matching the dashboard's `brandButtonStyle`.
    func accentFill(autoGradient: Bool) -> AnyShapeStyle {
        if autoGradient, let hex = accentHex, let dark = parseHexColor(darkenHex(hex)) {
            // CSS 155deg: 0 degrees is up, clockwise, so the vector is
            // (sin θ, −cos θ) in y-down space.
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
        return AnyShapeStyle(colors.accent)
    }
}

extension AppwinTheme {
    init(branding: Branding, design: MessengerDesign = .defaults) {
        self = AppwinTheme()
        colors.accent = branding.accent
        colors.onAccent = branding.onAccent
        accentHex = branding.accentHex
        self.design = design
        radius.card = design.radius.value
    }
}

// MARK: - Colour helpers (matching the dashboard's messenger-design-utils)

func darkenHex(_ hex: String, amount: Double = 0.22) -> String {
    guard let rgb = parseHexRGB(hex) else { return hex }
    func clamp(_ n: Double) -> Int {
        Int(max(0, min(255, round(n * (1 - amount)))))
    }
    let r = clamp(rgb.r * 255)
    let g = clamp(rgb.g * 255)
    let b = clamp(rgb.b * 255)
    return String(format: "#%02X%02X%02X", r, g, b)
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

private struct AppwinThemeKey: EnvironmentKey {
    static let defaultValue = AppwinTheme()
}

extension EnvironmentValues {
    var appwinTheme: AppwinTheme {
        get { self[AppwinThemeKey.self] }
        set { self[AppwinThemeKey.self] = newValue }
    }
}

extension View {
    func appwinTheme(_ theme: AppwinTheme) -> some View {
        environment(\.appwinTheme, theme)
    }
}
