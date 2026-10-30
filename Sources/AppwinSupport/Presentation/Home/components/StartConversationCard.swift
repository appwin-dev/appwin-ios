//
//  StartConversationCard.swift
//  AppwinSupport
//
//  CTA « Envoyer un message au support » - Figma support-home 40:6478.
//

import SwiftUI

struct StartConversationCard: View {
    @Environment(\.appwinTheme) private var theme

    var body: some View {
        HStack(spacing: 8) {
            SolarIcon(kind: .plain2, color: theme.colors.onAccent, size: 20)

            Text(SupportStrings.sendToSupport)
                .font(.system(size: 14, weight: .medium))
                .foregroundColor(theme.colors.onAccent)
                .lineLimit(1)
                .minimumScaleFactor(0.85)

            Spacer(minLength: 0)
        }
        .padding(20)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background {
            RoundedRectangle(cornerRadius: theme.radius.card, style: .continuous)
                .fill(theme.accentFill(autoGradient: theme.design.autoGradient))
                .overlay(
                    RoundedRectangle(cornerRadius: theme.radius.card, style: .continuous)
                        .strokeBorder(Color.white.opacity(0.12), lineWidth: 3)
                )
        }
        .shadow(color: AppwinTokens.shadowLow, radius: 20, x: 0, y: 24)
    }
}
