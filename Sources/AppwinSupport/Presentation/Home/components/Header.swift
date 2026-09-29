//
//  Header.swift
//  AppwinSupport
//
//  Home bar: avatar, title, close.
//  Same content as the dashboard Personnaliser preview: agent name + agent
//  avatar (project logo when the studio has not set a custom one).
//

import SwiftUI

struct Header: View {
    let context: MessengerConfigContext
    let onClose: (() -> Void)?

    @Environment(\.appwinTheme) private var theme

    /// Prefer the resolved agent label (`Support {project}` when unset), then
    /// the project name. Never a hardcoded "Centre d'aide": that ignored the
    /// studio's Personnaliser settings.
    private var title: String {
        let agent = context.agentName.trimmingCharacters(in: .whitespacesAndNewlines)
        if !agent.isEmpty { return agent }
        return context.projectName
    }

    var body: some View {
        HStack(spacing: 10) {
            AppwinAvatar(
                name: title,
                avatarURL: context.agentAvatarUrl ?? context.projectLogoUrl,
                size: 20,
                font: .system(size: 8, weight: .semibold),
                fallbackStyle: .project
            )

            Text(title)
                .font(.system(size: 12, weight: .medium))
                .foregroundColor(theme.colors.textPrimary)
                .lineLimit(1)

            Spacer(minLength: 0)

            if let onClose {
                AppwinIconButton(.close, action: onClose)
                    .accessibilityLabel(SupportStrings.close)
            }
        }
    }
}
