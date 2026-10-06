//
//  AppwinNavBar.swift
//  AppwinSupport
//
//  Bar of the pushed screens (thread, inbox, FAQ article): Figma
//  button/icon-native back on the left, title centred, on bg/page.
//

import SwiftUI

struct AppwinNavBar: View {
    let title: String
    let onBack: () -> Void

    @Environment(\.appwinTheme) private var theme

    var body: some View {
        ZStack {
            Text(title)
                .font(.system(size: 16, weight: .medium))
                .foregroundColor(theme.colors.textPrimary)
                .lineLimit(1)
                // Clears the 38pt button on both sides so the title stays centred.
                .padding(.horizontal, 54)

            HStack {
                AppwinIconButton(.altArrowLeft, style: .glass, size: 38, action: onBack)
                    .accessibilityLabel(SupportStrings.back)
                Spacer(minLength: 0)
            }
        }
        .padding(16)
    }
}
