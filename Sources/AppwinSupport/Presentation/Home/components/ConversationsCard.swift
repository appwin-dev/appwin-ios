//
//  ConversationsCard.swift
//  AppwinSupport
//
//  Carte « Ma messagerie ».
//

import SwiftUI

struct ConversationsCard: View {
    var hasUnread: Bool = false

    @Environment(\.appwinTheme) private var theme

    private let cardBorder = Color(hex: 0xF1F5F9)

    var body: some View {
        HStack(spacing: 10) {
            ZStack(alignment: .topTrailing) {
                SolarIcon(kind: .inbox, color: theme.colors.textPrimary, size: 16)
                if hasUnread {
                    Circle()
                        .fill(theme.colors.accent)
                        .frame(width: 8, height: 8)
                        .offset(x: 3, y: -3)
                }
            }

            Text(SupportStrings.messaging)
                .font(.system(size: 12, weight: .medium))
                .foregroundColor(theme.colors.textPrimary)
                .lineLimit(1)

            Spacer(minLength: 0)

            SolarIcon(kind: .altArrowRight, color: theme.colors.textPrimary, size: 12)
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.white, in: RoundedRectangle(cornerRadius: theme.radius.card, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: theme.radius.card, style: .continuous)
                .strokeBorder(cardBorder, lineWidth: 1)
        )
    }
}
