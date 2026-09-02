//
//  Header.swift
//  AppwinSupport
//
//  Home bar: avatar, title, close.
//

import SwiftUI

struct Header: View {
    let context: MessengerConfigContext
    let onClose: () -> Void

    @Environment(\.appwinTheme) private var theme

    var body: some View {
        HStack(spacing: 10) {
            AppwinAvatar(
                name: context.projectName,
                avatarURL: context.projectLogoUrl,
                size: 20,
                font: .system(size: 8, weight: .semibold)
            )

            Text("Centre d'aide")
                .font(.system(size: 12, weight: .medium))
                .foregroundColor(theme.colors.textPrimary)
                .lineLimit(1)

            Spacer(minLength: 0)

            Button(action: onClose) {
                SolarIcon(kind: .close, color: theme.colors.textPrimary, size: 20)
            }
            .frame(width: 28, height: 28)
            .accessibilityLabel("Fermer")
        }
    }
}
