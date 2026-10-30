// Studio-driven messenger config: branding (colours) plus feature flags
// (`modules`). `version` is the SDK cache's ETag, used for If-None-Match. Pure
// config, with no user data. Network mapping lives in
// `MessengerConfigDTO.toDomain()`.

import Foundation

struct MessengerConfig: Equatable {
    let branding: Branding
    let modules: SdkModules
    let messaging: MessengerMessaging
    let design: MessengerDesign
    let context: MessengerConfigContext
    let version: Int

    /// Uncustomised default (version 0): native theme, everything enabled.
    static let defaults = MessengerConfig(
        branding: .defaults,
        modules: .defaults,
        messaging: .defaults,
        design: .defaults,
        context: .defaults,
        version: 0
    )
}
