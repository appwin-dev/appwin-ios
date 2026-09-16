// The design system's container: a rounded surface with a soft shadow, like an
// Intercom card. Exposed as a modifier so it applies to any content:
//
//     VStack { … }
//         .appwinCard()              // padding, fill, radius, shadow
//     Text("…")
//         .appwinCard(padding: 0)     // no inner padding, for an already-padded row
//
// Values come from AppwinTokens alone.

import SwiftUI

struct AppwinCardModifier: ViewModifier {
    var padding: CGFloat = 16
    var cornerRadius: CGFloat = 16
    /// Soft drop shadow. `false` gives a flat, bordered card.
    var elevated: Bool = true

    func body(content: Content) -> some View {
        content
            .padding(padding)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(AppwinTokens.surface)
            .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .strokeBorder(AppwinTokens.border, lineWidth: elevated ? 0 : 1)
            )
            .shadow(
                color: elevated ? AppwinTokens.shadowSmooth : .clear,
                radius: 12, x: 0, y: 4
            )
    }
}

extension View {
    /// Wraps the content in an Intercom card: surface, radius and soft shadow.
    func appwinCard(
        padding: CGFloat = 16,
        cornerRadius: CGFloat = 16,
        elevated: Bool = true
    ) -> some View {
        modifier(AppwinCardModifier(padding: padding, cornerRadius: cornerRadius, elevated: elevated))
    }
}

// MARK: - Preview

#Preview {
    VStack(spacing: 16) {
        VStack(alignment: .leading, spacing: 6) {
            Text("Une question ?").appwinText(.headline)
            Text("On te répond en quelques minutes.").appwinText(.bodyS, color: AppwinTokens.textMedium)
        }
        .appwinCard()

        Text("Carte plate (bordée)").appwinText(.bodyM).appwinCard(elevated: false)
    }
    .padding()
    .background(AppwinTokens.surfaceMuted)
}
