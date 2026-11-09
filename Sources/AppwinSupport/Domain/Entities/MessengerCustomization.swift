import Foundation
import CoreGraphics
import AppwinCore

enum MessengerAvatarSource: String, Codable, Equatable {
    case projectLogo = "project_logo"
    case custom
}

struct MessengerMessaging: Equatable {
    var agentName: String?
    var avatarSource: MessengerAvatarSource
    var agentAvatarUrl: URL?
    var welcomeMessage: String
    var welcomeMessageEnabled: Bool

    static let defaults = MessengerMessaging(
        agentName: nil,
        avatarSource: .projectLogo,
        agentAvatarUrl: nil,
        welcomeMessage: "",
        welcomeMessageEnabled: true
    )
}

enum MessengerRadius: String, Codable, Equatable {
    case low, medium, high, max

    var value: CGFloat {
        switch self {
        case .low: return 8
        case .medium: return 12
        case .high: return 16
        // Same "Maximal" as Community (33): at 24 it barely read rounder than high.
        case .max: return 33
        }
    }
}

enum MessengerBannerSource: String, Codable, Equatable {
    case preset, custom, none
}

enum MessengerPresetBannerId: String, Codable, Equatable {
    case emojis, amicale, discret, photo, icon, serious
}

/// `system` follows the host app's appearance; `light` / `dark` force it.
enum MessengerColorScheme: String, Codable, Equatable, Sendable {
    case system, light, dark
}

/// Gray family, coolest to warmest (Tailwind slate..stone).
enum MessengerGrayWarmth: String, Codable, Equatable, Sendable {
    case slate, gray, zinc, neutral, stone
}

struct MessengerDesign: Equatable {
    var autoGradient: Bool
    var colorScheme: MessengerColorScheme
    var grayWarmth: MessengerGrayWarmth
    var radius: MessengerRadius
    var bannerSource: MessengerBannerSource
    var presetBannerId: MessengerPresetBannerId
    var bannerUrl: URL?
    /// 0 = haut, 100 = bas - cadrage vertical `object-cover`.
    var bannerFocusY: Double
    /// First gradient stop picked by the studio; `nil` = derived tint.
    var gradientHex: String? = nil

    static let defaults = MessengerDesign(
        autoGradient: true,
        colorScheme: .light,
        grayWarmth: .slate,
        radius: .high,
        bannerSource: .preset,
        presetBannerId: .emojis,
        bannerUrl: nil,
        bannerFocusY: 50
    )
}

struct MessengerConfigContext: Equatable {
    var projectName: String
    var projectLogoUrl: URL?
    var agentName: String
    var agentAvatarUrl: URL?
    var assetsBaseUrl: URL

    /// Fallback offline / avant configure - pas de lecture AppwinCore (MainActor).
    static let defaults = MessengerConfigContext(
        projectName: "App",
        projectLogoUrl: nil,
        agentName: "Support",
        agentAvatarUrl: nil,
        assetsBaseUrl: URL(string: "http://localhost:3001")!
    )

    /// Defaults with `assetsBaseUrl` derived from the API, for dev devices.
    @MainActor
    static var resolvedDefaults: MessengerConfigContext {
        MessengerConfigContext(
            projectName: "App",
            projectLogoUrl: nil,
            agentName: "Support",
            agentAvatarUrl: nil,
            assetsBaseUrl: resolvedAssetsBaseUrl(nil)
        )
    }

    /// Normalises the assets URL: when the server returns `localhost`, rewrite
    /// it with the host from `AppwinCore.baseUrl` (same machine, port 3001) so a
    /// physical device can load the banners.
    @MainActor
    static func assetsBaseUrl(from raw: String) -> URL {
        resolvedAssetsBaseUrl(URL(string: raw))
    }

    @MainActor
    static func resolvedAssetsBaseUrl(_ preferred: URL?) -> URL {
        if let preferred, let host = preferred.host, host != "localhost", host != "127.0.0.1" {
            return preferred
        }
        if let api = URL(string: AppwinCore.baseUrl), let host = api.host {
            var components = URLComponents()
            components.scheme = api.scheme ?? "http"
            components.host = host
            components.port = 3001
            if let url = components.url { return url }
        }
        return preferred ?? URL(string: "http://localhost:3001")!
    }
}
