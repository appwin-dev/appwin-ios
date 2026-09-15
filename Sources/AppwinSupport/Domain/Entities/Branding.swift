// Brand colour, driven by the studio from the dashboard. The visual part of
// `MessengerConfig`; the `version` (ETag) lives on `MessengerConfig`, not here.
// Network mapping lives in `MessengerConfigDTO.toDomain()`.

import SwiftUI

struct Branding: Equatable {
    let accent: Color
    let onAccent: Color
    /// `#RRGGBB` for gradients, matching the dashboard's `brandButtonStyle`.
    let accentHex: String?

    init(accent: Color, onAccent: Color, accentHex: String? = nil) {
        self.accent = accent
        self.onAccent = onAccent
        self.accentHex = accentHex
    }

    /// The uncustomised look, meaning the SDK's native theme. Applied while no
    /// customisation exists (version 0) or before the first fetch, to avoid a flash.
    static let defaults = Branding(
        accent: AppwinTokens.accent,
        onAccent: AppwinTokens.textOnBrand,
        accentHex: nil
    )
}
