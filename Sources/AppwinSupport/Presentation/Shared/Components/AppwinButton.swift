// Design-system button, exposed as a `ButtonStyle` so it applies to a standard
// `Button`:
//
//     Button("Start a conversation") { … }
//         .buttonStyle(.appwinPrimary)
//
// Three variants: primary (filled accent), secondary (surface with a light
// border) and ghost (accent text alone).
//
// The style reads the static AppwinTokens rather than the Environment, which
// makes it usable anywhere with no wiring.

import SwiftUI

enum AppwinButtonVariant {
    case primary, secondary, ghost
}

struct AppwinButtonStyle: ButtonStyle {
    var variant: AppwinButtonVariant = .primary
    /// Full width by default, like the Intercom CTA.
    var fullWidth: Bool = true

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(AppwinTypography.font(.bodyM).weight(.semibold))
            .foregroundColor(foreground)
            .frame(maxWidth: fullWidth ? .infinity : nil)
            .padding(.vertical, 14)
            .padding(.horizontal, 20)
            .background(background(pressed: configuration.isPressed))
            .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .strokeBorder(borderColor, lineWidth: variant == .secondary ? 1 : 0)
            )
            .scaleEffect(configuration.isPressed ? 0.98 : 1)
            .animation(.easeOut(duration: 0.12), value: configuration.isPressed)
    }

    // MARK: - Colours per variant

    private var foreground: Color {
        switch variant {
        case .primary:   return AppwinTokens.textOnBrand
        case .secondary: return AppwinTokens.textHigh
        case .ghost:     return AppwinTokens.accent
        }
    }

    private func background(pressed: Bool) -> Color {
        switch variant {
        case .primary:   return pressed ? AppwinPalette.brandPressed : AppwinTokens.accent
        case .secondary: return pressed ? AppwinPalette.grey100 : AppwinTokens.surface
        case .ghost:     return pressed ? AppwinPalette.grey100 : .clear
        }
    }

    private var borderColor: Color {
        variant == .secondary ? AppwinTokens.border : .clear
    }
}

// MARK: - `.buttonStyle(.appwinPrimary)` shorthands

extension ButtonStyle where Self == AppwinButtonStyle {
    static var appwinPrimary: AppwinButtonStyle { .init(variant: .primary) }
    static var appwinSecondary: AppwinButtonStyle { .init(variant: .secondary) }
    static var appwinGhost: AppwinButtonStyle { .init(variant: .ghost, fullWidth: false) }
}

// MARK: - Preview

#Preview {
    VStack(spacing: 12) {
        Button("Démarrer une conversation") {}.buttonStyle(.appwinPrimary)
        Button("Voir mes conversations") {}.buttonStyle(.appwinSecondary)
        Button("Annuler") {}.buttonStyle(.appwinGhost)
    }
    .padding()
    .background(AppwinTokens.surfaceMuted)
}
