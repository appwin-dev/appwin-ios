//
//  ConversationsCard.swift
//  AppwinSupport
//
//  Carte « Ma messagerie » - Figma support-home 40:6481.
//

import SwiftUI

struct ConversationsCard: View {
    var hasUnread: Bool = false

    @Environment(\.appwinTheme) private var theme

    var body: some View {
        HStack(spacing: 8) {
            ZStack(alignment: .topTrailing) {
                SolarIcon(kind: .inbox, color: theme.colors.textPrimary, size: 20)
                if hasUnread {
                    Circle()
                        .fill(theme.colors.accent)
                        .frame(width: 8, height: 8)
                        .offset(x: 3, y: -3)
                }
            }

            Text(SupportStrings.messaging)
                .font(.system(size: 14, weight: .medium))
                .foregroundColor(theme.colors.textPrimary)
                .lineLimit(1)

            Spacer(minLength: 0)

            SolarIcon(kind: .altArrowRight, color: AppwinTokens.iconLow, size: 16)
        }
        .appwinCard(cornerRadius: theme.radius.card)
    }
}
