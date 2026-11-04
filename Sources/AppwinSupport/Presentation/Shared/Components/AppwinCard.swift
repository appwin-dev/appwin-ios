// The Figma container card (bg/container on the bg/page panel): a white
// rounded surface with no border and no shadow, the contrast being the
// surface/page difference (support-home 40:6481). Radius comes from the theme so
// the studio's "Arrondis" setting reaches every card.
//
//     HStack { … }.appwinCard(cornerRadius: theme.radius.card)

import SwiftUI

struct AppwinCardModifier: ViewModifier {
    var padding: CGFloat = 20
    var cornerRadius: CGFloat
    var fill: Color = AppwinTokens.surface

    func body(content: Content) -> some View {
        content
            .padding(padding)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(fill, in: RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
            .contentShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
    }
}

extension View {
    func appwinCard(
        padding: CGFloat = 20,
        cornerRadius: CGFloat,
        fill: Color = AppwinTokens.surface
    ) -> some View {
        modifier(AppwinCardModifier(padding: padding, cornerRadius: cornerRadius, fill: fill))
    }
}

#Preview {
    VStack(spacing: 12) {
        Text("Ma messagerie").appwinText(.bodyM).appwinCard(cornerRadius: 16)
        Text("Bg low").appwinText(.bodyM).appwinCard(cornerRadius: 16, fill: AppwinTokens.surfaceMuted)
    }
    .padding(20)
    .background(AppwinTokens.surfacePage)
}
