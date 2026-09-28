//
//  AppwinRootView.swift
//  AppwinSupport
//
//  Root of the SwiftUI tree presented by `presentMessenger`. Observes the
//  `ConfigStore` to apply the theme derived from remote branding and triggers
//  its stale-while-revalidate refresh. When the colour changes, this re-render
//  propagates the new theme to the whole UI.
//

import SwiftUI

struct AppwinRootView<Content: View>: View {
    @ObservedObject var configStore: ConfigStore
    @ViewBuilder let content: () -> Content

    var body: some View {
        content()
            .appwinTheme(AppwinTheme(config: configStore.config))
            // Tokens UI = light only : figer le schéma évite les bandes sombres /
            // texte invisible quand l'app hôte est en dark mode.
            .preferredColorScheme(.light)
            .task { await configStore.refresh() }
    }
}
