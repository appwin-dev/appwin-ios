//
//  AppwinTokens.swift
//  AppwinSupport
//
//  Semantic tokens. Grays are dynamic (scheme + the config's gray warmth, see
//  AppwinGrays); brand and status colours are fixed.
//

import SwiftUI

enum AppwinTokens {

    // MARK: - Surface

    static let surface        = AppwinGrays.color(.surface) // bg/container
    static let surfaceMuted   = AppwinGrays.color(.raised)  // bg/low
    static let surfacePage    = AppwinGrays.color(.page)    // bg/page
    static let surfaceInverse = AppwinGrays.color(.text)

    // MARK: - Text

    static let textHigh    = AppwinGrays.color(.text)   // text/main
    static let textMedium  = AppwinGrays.color(.muted)  // text/secondary
    static let textLow     = AppwinGrays.color(.subtle) // text/subtle
    static let textOnBrand = AppwinPalette.onBrand

    // MARK: - Icon

    static let iconHigh    = AppwinGrays.color(.text)
    static let iconMedium  = AppwinGrays.color(.muted)
    static let iconLow     = AppwinGrays.color(.subtle)
    static let iconOnBrand = AppwinPalette.onBrand

    // MARK: - Border

    static let border       = AppwinGrays.color(.border)
    static let borderStrong = AppwinGrays.color(.subtle)

    // MARK: - Brand / Status

    static let accent  = AppwinPalette.brand
    static let danger  = AppwinPalette.danger
    static let success = AppwinPalette.success

    // MARK: - Shadow (effect-shadow-s / m)

    /// Figma shadow/low: agent bubble, composer, brand CTA.
    static let shadowLow         = Color(red: 23 / 255, green: 23 / 255, blue: 23 / 255).opacity(0.08)
    static let shadowSmooth      = Color(red: 2 / 255, green: 6 / 255, blue: 23 / 255).opacity(0.05)
    static let shadowIntense     = Color(red: 2 / 255, green: 6 / 255, blue: 23 / 255).opacity(0.1)
    static let shadowVeryIntense = Color(red: 2 / 255, green: 6 / 255, blue: 23 / 255).opacity(0.2)
}
