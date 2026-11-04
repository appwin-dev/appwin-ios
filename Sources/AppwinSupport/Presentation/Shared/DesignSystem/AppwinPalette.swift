//
//  AppwinPalette.swift
//  AppwinSupport
//
//  Raw colours, aligned with the Figma and dashboard tokens (`globals.css` light).
//

import SwiftUI

enum AppwinPalette {

    // MARK: - Slate scale (Figma / SaaS)

    static let grey00  = Color(hex: 0xFFFFFF)
    static let grey50  = Color(hex: 0xF9FAFC) // --bg-page
    static let grey100 = Color(hex: 0xF1F5F9) // --bg-subtle
    static let grey200 = Color(hex: 0xE2E8F0) // --border-default
    static let grey300 = Color(hex: 0xCBD5E1)
    static let grey400 = Color(hex: 0x94A3B8) // --text-tiertary
    static let grey500 = Color(hex: 0x64758B)
    static let grey600 = Color(hex: 0x475569)
    static let grey700 = Color(hex: 0x334156) // --text-secondary
    static let grey800 = Color(hex: 0x1E293B)
    static let grey900 = Color(hex: 0x0E172A) // --text-main

    // MARK: - Brand

    static let brand        = Color(hex: 0x3373F2)
    static let brandPressed = Color(hex: 0x255CCB)
    static let onBrand      = grey00

    // MARK: - Status

    static let success = Color(hex: 0x2BA84A)
    static let danger  = Color(hex: 0xE11D48)
    static let warning = Color(hex: 0xF5A623)
}

extension Color {
    init(hex: UInt32, alpha: Double = 1) {
        let r = Double((hex >> 16) & 0xFF) / 255
        let g = Double((hex >> 8) & 0xFF) / 255
        let b = Double(hex & 0xFF) / 255
        self.init(.sRGB, red: r, green: g, blue: b, opacity: alpha)
    }
}
