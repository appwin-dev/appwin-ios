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

    // MARK: - Surfaces adaptatives
    //
    // The feed must stay readable in light and dark, including when the host app
    // forces a mode, hence dynamic `UIColor`s rather than fixed colours.

    static let background = Color(uiColor: UIColor { trait in
        trait.userInterfaceStyle == .dark
            ? UIColor(red: 0.07, green: 0.07, blue: 0.09, alpha: 1)
            : UIColor(red: 0.973, green: 0.976, blue: 0.988, alpha: 1)
    })

    static let surface = Color(uiColor: UIColor { trait in
        trait.userInterfaceStyle == .dark
            ? UIColor(red: 0.106, green: 0.118, blue: 0.145, alpha: 1)
            : UIColor.white
    })

    static let border = Color(uiColor: UIColor { trait in
        trait.userInterfaceStyle == .dark
            ? UIColor(white: 1, alpha: 0.10)
            : UIColor(red: 0.886, green: 0.910, blue: 0.941, alpha: 1)
    })

    static let textPrimary = Color(uiColor: UIColor { trait in
        trait.userInterfaceStyle == .dark
            ? UIColor.white
            : UIColor(red: 0.055, green: 0.090, blue: 0.165, alpha: 1)
    })

    static let textSecondary = Color(uiColor: UIColor { trait in
        trait.userInterfaceStyle == .dark
            ? UIColor(white: 1, alpha: 0.72)
            : UIColor(red: 0.200, green: 0.255, blue: 0.337, alpha: 1)
    })

    static let textTertiary = Color(uiColor: UIColor { trait in
        trait.userInterfaceStyle == .dark
            ? UIColor(white: 1, alpha: 0.48)
            : UIColor(red: 0.580, green: 0.639, blue: 0.722, alpha: 1)
    })
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
