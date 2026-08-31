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
    let fontFamily: CommunityFontFamily
    /// PostScript name, when `fontFamily == .custom`.
    let fontFamilyName: String?
    let fontScale: CommunityFontScale
    let radius: CommunityRadius
    let colorScheme: CommunityColorScheme

    static let defaults = CommunityThemeConfig(
        primary: AppwinCommunityPalette.brand,
        primaryForeground: AppwinCommunityPalette.onBrand,
        primaryHex: "#3373F2",
        fontFamily: .system,
        fontFamilyName: nil,
        fontScale: .default,
        radius: .high,
        colorScheme: .system
    )
}

enum CommunityFontFamily: String, Equatable {
    case system, rounded, serif, monospace, custom

    /// Matching SwiftUI design. `custom` falls back to `.default` here: the
    /// named font is applied separately, by PostScript name.
    var design: Font.Design {
        switch self {
        case .rounded: return .rounded
        case .serif: return .serif
        case .monospace: return .monospaced
        case .system, .custom: return .default
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

    var value: CGFloat {
        switch self {
        case .low: return 8
        case .medium: return 14
        case .high: return 20
        case .max: return 28
        }
    }
}

enum CommunityColorScheme: String, Equatable {
    case system, light, dark

    /// `nil` means follow the system, forcing no `preferredColorScheme`.
    var preferred: ColorScheme? {
        switch self {
        case .system: return nil
        case .light: return .light
        case .dark: return .dark
        }
    }
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

    /// Permissive defaults except `enabled`: until the studio turns the
    /// community on, the SDK must not show an empty feed in production.
    static let defaults = CommunityFeatures(
        enabled: false,
        postsEnabled: true,
        commentsEnabled: true,
        repliesEnabled: true,
        imagesEnabled: true,
        reactionsEnabled: true,
        reactions: [.like],
        viewsEnabled: true,
        authorEditEnabled: true,
        translationEnabled: false,
        profilesEnabled: true,
        reportingEnabled: true
    )
}

enum CommunityReactionKind: String, Equatable, CaseIterable {
    case like, love, laugh, wow, sad

    var emoji: String {
        switch self {
        case .like: return "👍"
        case .love: return "❤️"
        case .laugh: return "😂"
        case .wow: return "😮"
        case .sad: return "😢"
        }
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
