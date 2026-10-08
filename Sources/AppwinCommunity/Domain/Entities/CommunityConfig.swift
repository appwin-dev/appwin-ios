// Studio-driven community config: theme, kill switches, limits. Pure config
// with no user data. Network mapping lives in `CommunityConfigDTO`.
//
// `version` is the SDK cache's ETag, used for If-None-Match. The moderation
// policy is deliberately absent: the server does not serve it to the SDK, since
// a member has no business reading the threshold they would have to dodge.

import SwiftUI

struct CommunityConfig: Equatable {
    let theme: CommunityThemeConfig
    let features: CommunityFeatures
    let limits: CommunityLimits
    let context: CommunityContext
    let version: Int

    /// Uncustomised default (version 0): native theme, community off.
    static let defaults = CommunityConfig(
        theme: .defaults,
        features: .defaults,
        limits: .defaults,
        context: .defaults,
        version: 0
    )
}

// MARK: - Theme

struct CommunityThemeConfig: Equatable {
    let primary: Color
    let primaryForeground: Color
    /// Kept as hex so a gradient can be derived (see `AppwinCommunityTheme`).
    let primaryHex: String
    /// Accent surfaces are a two-stop gradient instead of a flat fill.
    let autoGradient: Bool
    /// Start stop of the gradient; `nil` derives it from the accent.
    let gradientHex: String?
    /// Drop shadow under the compose and send buttons.
    let buttonShadow: Bool
    /// `nil` = the accent's dark shade at 37 %.
    let buttonShadowHex: String?
    /// `nil` falls back to the project name - what the studio wants by default.
    let headerTitle: String?
    let headerTitleVisible: Bool
    let fontFamily: CommunityFontFamily
    /// PostScript name, when `fontFamily == .custom`.
    let fontFamilyName: String?
    let fontScale: CommunityFontScale
    let radius: CommunityRadius
    let colorScheme: CommunityColorScheme
    let grayWarmth: CommunityGrayWarmth

    static let defaults = CommunityThemeConfig(
        primary: AppwinCommunityPalette.brand,
        primaryForeground: AppwinCommunityPalette.onBrand,
        primaryHex: "#FA7315",
        autoGradient: false,
        gradientHex: nil,
        buttonShadow: true,
        buttonShadowHex: nil,
        headerTitle: nil,
        headerTitleVisible: true,
        fontFamily: .inter,
        fontFamilyName: nil,
        fontScale: .default,
        radius: .high,
        // Light by default: the SDK has always been light, and an app must not
        // turn dark before its studio chooses it.
        colorScheme: .light,
        grayWarmth: .slate
    )
}

enum CommunityFontFamily: String, Equatable {
    case inter, system, rounded, serif, monospace, custom

    /// Matching SwiftUI design. `custom` falls back to `.default` here: the
    /// named font is applied separately, by PostScript name. `inter` also maps
    /// to `.default`: the face itself is resolved by name in
    /// `CommunityTheme.font(_:weight:)`, and the system design is what we land
    /// on if the host app has not bundled it.
    var design: Font.Design {
        switch self {
        case .rounded: return .rounded
        case .serif: return .serif
        case .monospace: return .monospaced
        case .inter, .system, .custom: return .default
        }
    }
}

enum CommunityFontScale: String, Equatable {
    case compact, `default`, comfortable, large

    /// Multiplier applied on top of the Dynamic Type size.
    var multiplier: CGFloat {
        switch self {
        case .compact: return 0.9
        case .default: return 1
        case .comfortable: return 1.08
        case .large: return 1.2
        }
    }
}

enum CommunityRadius: String, Equatable {
    case low, medium, high, max

    /// `high` is the mock's own `post-card` radius (28.24 of a 473-wide
    /// artboard) brought back to device points, like every other measurement
    /// taken off that frame.
    var value: CGFloat {
        switch self {
        case .low: return 8
        case .medium: return 15
        case .high: return 23
        case .max: return 33
        }
    }
}

enum CommunityColorScheme: String, Equatable {
    case system, light, dark

    /// `nil` means follow the host app, forcing no `preferredColorScheme`.
    var preferred: ColorScheme? {
        switch self {
        case .system: return nil
        case .light: return .light
        case .dark: return .dark
        }
    }
}

/// Gray family, coolest to warmest (Tailwind slate..stone), shared with Support.
enum CommunityGrayWarmth: String, Equatable, Sendable {
    case slate, gray, zinc, neutral, stone
}

// MARK: - Kill switches

struct CommunityFeatures: Equatable {
    let enabled: Bool
    let postsEnabled: Bool
    let commentsEnabled: Bool
    let repliesEnabled: Bool
    let imagesEnabled: Bool
    let reactionsEnabled: Bool
    let reactions: [CommunityReactionKind]
    let viewsEnabled: Bool
    let authorEditEnabled: Bool
    let translationEnabled: Bool
    let profilesEnabled: Bool
    let reportingEnabled: Bool
    /// Who may post images, videos and polls, and who may comment.
    let permissions: CommunityPermissions

    /// The emoji bar on long press: only when the studio offers more than the heart.
    var offersEmojiReactions: Bool { reactionsEnabled && reactions.count > 1 }

    /// Permissive defaults except `enabled`: until the studio turns the
    /// community on, the SDK must not show an empty feed in production.
    static let defaults = CommunityFeatures(
        enabled: false,
        postsEnabled: true,
        commentsEnabled: true,
        repliesEnabled: true,
        imagesEnabled: true,
        reactionsEnabled: true,
        reactions: CommunityReactionKind.allCases,
        viewsEnabled: true,
        authorEditEnabled: true,
        translationEnabled: false,
        profilesEnabled: true,
        reportingEnabled: true,
        permissions: .everyone
    )
}

/// Who may do something in the community, set by the studio per capability.
enum CommunityAudience: String, Equatable {
    case nobody, admins, everyone

    /// `admins` covers moderators too: they act for the studio inside the app.
    func allows(_ role: CommunityMemberRole) -> Bool {
        switch self {
        case .everyone: return true
        case .nobody: return false
        case .admins: return role != .member
        }
    }
}

struct CommunityPermissions: Equatable {
    let images: CommunityAudience
    let videos: CommunityAudience
    let polls: CommunityAudience
    let comments: CommunityAudience

    static let everyone = CommunityPermissions(
        images: .everyone,
        videos: .everyone,
        polls: .everyone,
        comments: .everyone
    )
}

/// In the order of the emoji bar (Figma 178:2456).
enum CommunityReactionKind: String, Equatable, Hashable, CaseIterable {
    case love, like, laugh, fire, wow, clap, eyes, sad, pray, bangbang, angry

    var emoji: String {
        switch self {
        case .love: return "❤️"
        case .like: return "👍"
        case .laugh: return "😂"
        case .fire: return "🔥"
        case .wow: return "😲"
        case .clap: return "👏"
        case .eyes: return "👀"
        case .sad: return "😢"
        case .pray: return "🙏"
        case .bangbang: return "‼️"
        case .angry: return "😡"
        }
    }

    /// Short-tap kind: heart (`love`) when the studio offers it, else the first
    /// configured kind. Picker `like` stays 👍 and must not share this default.
    static func defaultTap(from available: [CommunityReactionKind]) -> CommunityReactionKind {
        available.first(where: { $0 == .love }) ?? available.first ?? .love
    }
}

// MARK: - Limites

struct CommunityLimits: Equatable {
    let postMaxLength: Int
    let commentMaxLength: Int
    let maxImagesPerPost: Int
    /// Lines rendered before "see more" in the feed.
    let feedPreviewLines: Int

    static let defaults = CommunityLimits(
        postMaxLength: 1500,
        commentMaxLength: 1000,
        maxImagesPerPost: 4,
        feedPreviewLines: 4
    )
}

// MARK: - Contexte

struct CommunityContext: Equatable {
    let projectName: String
    let projectLogoUrl: URL?

    static let defaults = CommunityContext(projectName: "", projectLogoUrl: nil)
}
