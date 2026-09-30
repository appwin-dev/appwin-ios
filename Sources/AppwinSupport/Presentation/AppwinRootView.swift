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
    @Environment(\.colorScheme) private var hostScheme
    @ViewBuilder let content: () -> Content

    var body: some View {
        let design = configStore.config.design
        // Read by the dynamic gray tokens when SwiftUI resolves them, so it has
        // to be set before the children render.
        AppwinGrays.warmth = design.grayWarmth
        return content()
            // A warmth change swaps every gray: rebuild rather than leave views
            // that only read static tokens on the previous family.
            .id(design.grayWarmth)
            .appwinTheme(AppwinTheme(config: configStore.config))
            .environment(\.colorScheme, design.colorScheme.forced ?? hostScheme)
            // Also reaches the UIKit chrome of the presented sheet (keyboard,
            // safe area); nil lets `system` follow the host app.
            .preferredColorScheme(design.colorScheme.forced)
            .task { await configStore.refresh() }
    }
}
