//
//  StartConversationCard.swift
//  AppwinSupport
//
//  CTA « Envoyer un message au support ».
//

import SwiftUI

struct StartConversationCard: View {
    @Environment(\.appwinTheme) private var theme

    var body: some View {
        HStack(spacing: 10) {
            SolarIcon(kind: .plain2, color: theme.colors.onAccent, size: 16)

            Text("Envoyer un message au support")
                .font(.system(size: 12, weight: .medium))
                .foregroundColor(theme.colors.onAccent)
                .lineLimit(1)
                .minimumScaleFactor(0.85)

            Spacer(minLength: 0)
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background {
            RoundedRectangle(cornerRadius: theme.radius.card, style: .continuous)
                .fill(theme.accentFill(autoGradient: theme.design.autoGradient))
                .overlay(
                    RoundedRectangle(cornerRadius: theme.radius.card, style: .continuous)
                        .strokeBorder(Color.white.opacity(0.2), lineWidth: 2)
                )
        }
    }
}
