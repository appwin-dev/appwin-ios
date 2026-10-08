//
//  AppwinCommunityGrays.swift
//  AppwinCommunity
//
//  Gray scales for the `grayWarmth` knob, same table as AppwinSupport's
//  `AppwinGrays` and the web widget (duplicated for the reason given in
//  AppwinCommunityPalette). Figma Tokens-color mapping: page=50/950 (bg/page),
//  surface=white/900 (bg/container), raised=100/800 (bg/low, border/low),
//  border=200/700 (bg/medium, border/medium), text=900/white, muted=700/400,
//  subtle=400/500.
//

import SwiftUI
import UIKit

enum AppwinCommunityGrays {
    enum Role: Sendable {
        case page, surface, raised, text, muted, subtle, border
    }

    /// Written by `communityThemed(config:)` before the tree renders. The
    /// colours below are dynamic: light/dark comes from the trait (host or
    /// forced scheme), the family from this value, read when SwiftUI resolves.
    nonisolated(unsafe) static var warmth: CommunityGrayWarmth = .slate

    static func color(_ role: Role) -> Color {
        Color(UIColor { traits in
            let hex = value(role, warmth: warmth, dark: traits.userInterfaceStyle == .dark)
            return UIColor(
                red: CGFloat((hex >> 16) & 0xFF) / 255,
                green: CGFloat((hex >> 8) & 0xFF) / 255,
                blue: CGFloat(hex & 0xFF) / 255,
                alpha: 1
            )
        })
    }

    // Columns: page, surface, raised, text, muted, subtle, border.
    private static func value(_ role: Role, warmth: CommunityGrayWarmth, dark: Bool) -> UInt32 {
        let row: [UInt32]
        switch (warmth, dark) {
        case (.slate, false):   row = [0xF8FAFC, 0xFFFFFF, 0xF1F5F9, 0x0F172A, 0x334155, 0x94A3B8, 0xE2E8F0]
        case (.slate, true):    row = [0x020617, 0x0F172A, 0x1E293B, 0xFFFFFF, 0x94A3B8, 0x64748B, 0x334155]
        case (.gray, false):    row = [0xF9FAFB, 0xFFFFFF, 0xF3F4F6, 0x111827, 0x374151, 0x9CA3AF, 0xE5E7EB]
        case (.gray, true):     row = [0x030712, 0x111827, 0x1F2937, 0xFFFFFF, 0x9CA3AF, 0x6B7280, 0x374151]
        case (.zinc, false):    row = [0xFAFAFA, 0xFFFFFF, 0xF4F4F5, 0x18181B, 0x3F3F46, 0xA1A1AA, 0xE4E4E7]
        case (.zinc, true):     row = [0x09090B, 0x18181B, 0x27272A, 0xFFFFFF, 0xA1A1AA, 0x71717A, 0x3F3F46]
        case (.neutral, false): row = [0xFAFAFA, 0xFFFFFF, 0xF5F5F5, 0x171717, 0x404040, 0xA3A3A3, 0xE5E5E5]
        case (.neutral, true):  row = [0x0A0A0A, 0x171717, 0x262626, 0xFFFFFF, 0xA3A3A3, 0x737373, 0x404040]
        case (.stone, false):   row = [0xFAFAF9, 0xFFFFFF, 0xF5F5F4, 0x1C1917, 0x44403C, 0xA8A29E, 0xE7E5E4]
        case (.stone, true):    row = [0x0C0A09, 0x1C1917, 0x292524, 0xFFFFFF, 0xA8A29E, 0x78716C, 0x44403C]
        }
        switch role {
        case .page: return row[0]
        case .surface: return row[1]
        case .raised: return row[2]
        case .text: return row[3]
        case .muted: return row[4]
        case .subtle: return row[5]
        case .border: return row[6]
        }
    }
}

extension View {
    /// Theme, gray family and colour scheme from the config, in one place for
    /// every root (feed, push-opened post, unavailable screen).
    func communityThemed(config: CommunityConfig) -> some View {
        modifier(CommunityThemedModifier(config: config))
    }
}

private struct CommunityThemedModifier: ViewModifier {
    let config: CommunityConfig
    @Environment(\.colorScheme) private var hostScheme

    func body(content: Content) -> some View {
        let scheme = config.theme.colorScheme.preferred
        // Read by the dynamic gray tokens when SwiftUI resolves them, so it has
        // to be set before the children render.
        AppwinCommunityGrays.warmth = config.theme.grayWarmth
        return content
            // A warmth change swaps every gray: rebuild rather than leave views
            // that only read static tokens on the previous family.
            .id(config.theme.grayWarmth)
            .communityTheme(CommunityTheme(config: config))
            .environment(\.colorScheme, scheme ?? hostScheme)
            // Also reaches the UIKit chrome of a presented screen (keyboard,
            // safe area); nil lets `system` follow the host app.
            .preferredColorScheme(scheme)
    }
}
