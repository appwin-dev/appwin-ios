//
//  AppwinTokens.swift
//  AppwinSupport
//
//  Semantic tokens, mirroring `packages/ui/src/styles/globals.css` (light).
//

import SwiftUI

enum AppwinTokens {

    // MARK: - Surface

    static let surface        = AppwinPalette.grey00   // --bg-elevated / container
    static let surfaceMuted   = AppwinPalette.grey100  // --bg-subtle
    static let surfacePage    = AppwinPalette.grey50   // --bg-page
    static let surfaceInverse = AppwinPalette.grey900

    // MARK: - Text

    static let textHigh    = AppwinPalette.grey900  // --text-main
    static let textMedium  = AppwinPalette.grey700  // --text-secondary
    static let textLow     = AppwinPalette.grey400  // --text-tiertary
    static let textOnBrand = AppwinPalette.onBrand

    // MARK: - Icon

    static let iconHigh    = AppwinPalette.grey900
    static let iconMedium  = AppwinPalette.grey700
    static let iconLow     = AppwinPalette.grey400
    static let iconOnBrand = AppwinPalette.onBrand

    // MARK: - Border

    static let border       = AppwinPalette.grey200 // --border-default
    static let borderStrong = AppwinPalette.grey300

    // MARK: - Brand / Status

    static let accent  = AppwinPalette.brand
    static let danger  = AppwinPalette.danger
    static let success = AppwinPalette.success

    // MARK: - Shadow (effect-shadow-s / m)

    static let shadowSmooth      = Color(red: 2 / 255, green: 6 / 255, blue: 23 / 255).opacity(0.05)
    static let shadowIntense     = Color(red: 2 / 255, green: 6 / 255, blue: 23 / 255).opacity(0.1)
    static let shadowVeryIntense = Color(red: 2 / 255, green: 6 / 255, blue: 23 / 255).opacity(0.2)
}
