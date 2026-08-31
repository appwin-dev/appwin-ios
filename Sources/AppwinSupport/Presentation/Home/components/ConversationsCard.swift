//
//  ConversationsCard.swift
//  AppwinSupport
//
//  Carte « Ma messagerie ».
//

import SwiftUI

struct ConversationsCard: View {
    @Environment(\.appwinTheme) private var theme

    private let cardBorder = Color(hex: 0xF1F5F9)
    private let buttonHeight: CGFloat = 56

    var body: some View {
        HStack(spacing: 10) {
            SolarIcon(kind: .inbox, color: theme.colors.textPrimary, size: 18)

            Text("Ma messagerie")
                .font(.system(size: 14, weight: .medium))
                .foregroundColor(theme.colors.textPrimary)
                .lineLimit(1)

            Spacer(minLength: 0)

            SolarIcon(kind: .altArrowRight, color: theme.colors.textPrimary, size: 14)
        }
        .padding(.horizontal, 16)
        .frame(maxWidth: .infinity, minHeight: buttonHeight, maxHeight: buttonHeight, alignment: .leading)
        .background(Color.white)
        .clipShape(RoundedRectangle(cornerRadius: theme.radius.card, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: theme.radius.card, style: .continuous)
                .strokeBorder(cardBorder, lineWidth: 1)
        )
    }
}
