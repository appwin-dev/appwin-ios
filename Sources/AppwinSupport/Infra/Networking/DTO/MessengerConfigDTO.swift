// Network mirror of `PublicMessengerConfig` (packages/contracts).

import Foundation
import SwiftUI

struct MessengerConfigDTO: Codable {
    struct Colors: Codable {
        let primary: String
        let primaryForeground: String
    }
    struct Modules: Codable {
        let faqEnabled: Bool
    }
    struct Messaging: Codable {
        let agentName: String?
        let avatarSource: String?
        let agentAvatarUrl: String?
        let welcomeMessage: String?
        let welcomeMessageEnabled: Bool?
    }
    struct Design: Codable {
        let autoGradient: Bool?
        let radius: String?
        let bannerSource: String?
        let presetBannerId: String?
        let bannerUrl: String?
        let bannerFocusY: Double?
    }
    struct Context: Codable {
        let projectName: String
        let projectLogoUrl: String?
        let agentName: String
        let agentAvatarUrl: String?
        let assetsBaseUrl: String
    }

    let colors: Colors
    let modules: Modules?
    let messaging: Messaging?
    let design: Design?
    let context: Context?
    let version: Int
}

extension MessengerConfigDTO {
    @MainActor
    func toDomain() -> MessengerConfig {
        let modules = SdkModules(faqEnabled: self.modules?.faqEnabled ?? true)
        let messaging = mapMessaging()
        let design = mapDesign()
        let context = mapContext()
        return MessengerConfig(
            branding: brandingFromColors(),
            modules: modules,
            messaging: messaging,
            design: design,
            context: context,
            version: version
        )
    }

    private func mapMessaging() -> MessengerMessaging {
        guard let messaging else { return .defaults }
        return MessengerMessaging(
            agentName: messaging.agentName,
            avatarSource: MessengerAvatarSource(rawValue: messaging.avatarSource ?? "project_logo") ?? .projectLogo,
            agentAvatarUrl: messaging.agentAvatarUrl.flatMap(URL.init(string:)),
            welcomeMessage: messaging.welcomeMessage ?? "",
            welcomeMessageEnabled: messaging.welcomeMessageEnabled ?? true
        )
    }

    private func mapDesign() -> MessengerDesign {
        guard let design else { return .defaults }
        return MessengerDesign(
            autoGradient: design.autoGradient ?? true,
            radius: MessengerRadius(rawValue: design.radius ?? "high") ?? .high,
            bannerSource: MessengerBannerSource(rawValue: design.bannerSource ?? "preset") ?? .preset,
            presetBannerId: MessengerPresetBannerId(rawValue: design.presetBannerId ?? "emojis") ?? .emojis,
            bannerUrl: design.bannerUrl.flatMap(URL.init(string:)),
            bannerFocusY: design.bannerFocusY.map { min(100, max(0, $0)) } ?? 50
        )
    }

    @MainActor
    private func mapContext() -> MessengerConfigContext {
        let fallback = MessengerConfigContext.resolvedDefaults
        guard let context else { return fallback }
        return MessengerConfigContext(
            projectName: context.projectName,
            projectLogoUrl: context.projectLogoUrl.flatMap(URL.init(string:)),
            agentName: context.agentName,
            agentAvatarUrl: context.agentAvatarUrl.flatMap(URL.init(string:)),
            assetsBaseUrl: MessengerConfigContext.assetsBaseUrl(
                from: context.assetsBaseUrl
            )
        )
    }

    private func brandingFromColors() -> Branding {
        guard version > 0 else { return .defaults }
        guard let p = parseHexRGB(colors.primary) else { return .defaults }
        let accent = Color(.sRGB, red: p.r, green: p.g, blue: p.b, opacity: 1)
        let onAccent: Color
        if let f = parseHexRGB(colors.primaryForeground) {
            onAccent = Color(.sRGB, red: f.r, green: f.g, blue: f.b, opacity: 1)
        } else {
            onAccent = foregroundOn(r: p.r, g: p.g, b: p.b)
        }
        return Branding(accent: accent, onAccent: onAccent, accentHex: colors.primary)
    }
}

// MARK: - Helpers couleur
// `parseHexRGB` lives in Theme.swift, shared module-wide.

private func foregroundOn(r: Double, g: Double, b: Double) -> Color {
    func linear(_ c: Double) -> Double {
        c <= 0.03928 ? c / 12.92 : pow((c + 0.055) / 1.055, 2.4)
    }
    let luminance = 0.2126 * linear(r) + 0.7152 * linear(g) + 0.0722 * linear(b)
    return luminance > 0.5 ? Color(hex: 0x1F1F1F) : Color(hex: 0xFFFFFF)
}
