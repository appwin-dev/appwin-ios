//
//  Header.swift
//  AppwinSupport
//
//  Home bar: avatar, "Centre d'aide", close. Same as the dashboard preview;
//  the agent's name only appears once inside a conversation.
//

import SwiftUI

struct Header: View {
    let context: MessengerConfigContext
    let onClose: (() -> Void)?

    @Environment(\.appwinTheme) private var theme

    private var agentLabel: String {
        let agent = context.agentName.trimmingCharacters(in: .whitespacesAndNewlines)
        if !agent.isEmpty { return agent }
        return context.projectName
    }

    var body: some View {
        HStack(spacing: 8) {
            AppwinAvatar(
                name: agentLabel,
                avatarURL: context.agentAvatarUrl ?? context.projectLogoUrl,
                size: 24,
                font: .system(size: 10, weight: .semibold),
                fallbackStyle: .project
            )

            Text(SupportStrings.helpCenter)
                .font(.system(size: 16, weight: .medium))
                .foregroundColor(theme.colors.textPrimary)
                .lineLimit(1)

            Spacer(minLength: 0)

            if let onClose {
                AppwinIconButton(.close, style: .glass, size: 38, action: onClose)
                    .accessibilityLabel(SupportStrings.close)
            }
        }
        // Keeps the bar's height when embedded (no close button).
        .frame(minHeight: 38)
    }
}
