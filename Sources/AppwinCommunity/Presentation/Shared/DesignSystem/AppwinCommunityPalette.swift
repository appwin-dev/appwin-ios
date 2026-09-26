//
//  AppwinCommunityPalette.swift
//  AppwinCommunity
//
//  Raw colours, aligned with the Figma and dashboard tokens (`globals.css`).
//  Duplicated from AppwinSupport rather than shared through AppwinCore: Core is
//  the network and identity layer, and moving SwiftUI into it would make it
//  depend on the UI and force every product to inherit the previous one's design.
//

import SwiftUI

enum AppwinCommunityPalette {

    // MARK: - Neutral scale (light mode)

    static let grey00  = Color(communityHex: 0xFFFFFF)
    static let grey50  = Color(communityHex: 0xF9FAFC)
    static let grey100 = Color(communityHex: 0xF1F5F9)
    static let grey200 = Color(communityHex: 0xE2E8F0)
    static let grey300 = Color(communityHex: 0xCBD5E1)
    static let grey400 = Color(communityHex: 0x94A3B8)
    static let grey500 = Color(communityHex: 0x64758B)
    static let grey600 = Color(communityHex: 0x475569)
    static let grey700 = Color(communityHex: 0x334156)
    static let grey800 = Color(communityHex: 0x1E293B)
    static let grey900 = Color(communityHex: 0x0E172A)

    // MARK: - Marque

    /// orange/500 - accent of the community mock (Figma gradient/brand/Fire).
    static let brand   = Color(communityHex: 0xFA7315)
    static let onBrand = grey00

    // MARK: - States

    static let success = Color(communityHex: 0x2BA84A)
    static let danger  = Color(communityHex: 0xE11D48)
    static let warning = Color(communityHex: 0xF5A623)

    // MARK: - Surfaces (light only)
    //
    // Community is light-only (same lock as Support / Android). Fixed colours
    // avoid dark tokens leaking in when a host app forces dark mode.

    static let background = Color(communityHex: 0xF8F9FC)
    static let surface = grey00
    static let border = Color(communityHex: 0xE2E8F0)
    static let textPrimary = Color(communityHex: 0x0E172A)
    static let textSecondary = Color(communityHex: 0x334156)
    static let textTertiary = grey400
}

extension Color {
    /// Hex initialiser. Prefixed `community` so it does not collide with
    /// AppwinSupport's `init(hex:)` when a host app integrates both SDKs.
    init(communityHex hex: UInt32, alpha: Double = 1) {
        let r = Double((hex >> 16) & 0xFF) / 255
        let g = Double((hex >> 8) & 0xFF) / 255
        let b = Double(hex & 0xFF) / 255
        self.init(.sRGB, red: r, green: g, blue: b, opacity: alpha)
    }
}
