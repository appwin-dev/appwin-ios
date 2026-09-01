//
//  StartConversationCard.swift
//  AppwinSupport
//
//  CTA « Envoyer un message au support ».
//

import SwiftUI

struct StartConversationCard: View {
    @Environment(\.appwinTheme) private var theme

    private let buttonHeight: CGFloat = 56

    var body: some View {
        HStack(spacing: 10) {
            SolarIcon(kind: .plain2, color: theme.colors.onAccent, size: 18)

            Text("Envoyer un message au support")
                .font(.system(size: 14, weight: .medium))
                .foregroundColor(theme.colors.onAccent)
                .lineLimit(1)
                .minimumScaleFactor(0.85)

            Spacer(minLength: 0)
        }
        .padding(.horizontal, 16)
        .frame(maxWidth: .infinity, minHeight: buttonHeight, maxHeight: buttonHeight, alignment: .leading)
        .background {
            RoundedRectangle(cornerRadius: theme.radius.card, style: .continuous)
                .fill(theme.accentFill(autoGradient: theme.design.autoGradient))
                .overlay(
                    RoundedRectangle(cornerRadius: theme.radius.card, style: .continuous)
                        .strokeBorder(Color.white.opacity(0.2), lineWidth: 1.5)
                )
                .shadow(
                    color: Color(red: 2 / 255, green: 6 / 255, blue: 23 / 255).opacity(0.1),
                    radius: 4,
                    x: 0,
                    y: 4
                )
        }
    }
}
