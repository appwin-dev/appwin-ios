// swift-tools-version: 6.0

import PackageDescription

/*
 One package, several products.

 SPM resolves a git URL to the manifest at the repository root, so a repository
 serves exactly one package. Publishing Core and each product as separate
 repositories would make a studio add one package URL per product in Xcode and
 keep their versions aligned by hand. Declaring them as products of one package
 costs the studio one URL, and it picks the products it imports - the pattern
 `firebase-ios-sdk` uses for its twenty-odd products.

 The consequence to know: the products depend on each other through targets, not
 through versioned packages, so they ship under a single version. That is
 already the rule for the Android, Flutter and React Native artefacts.
 */
let package = Package(
  name: "Appwin",
  defaultLocalization: "en",
  platforms: [
    .iOS(.v16)
  ],
  products: [
    .library(name: "AppwinCore", targets: ["AppwinCore"]),
    .library(name: "AppwinSupport", targets: ["AppwinSupport"]),
    .library(name: "AppwinCommunity", targets: ["AppwinCommunity"]),
    .library(name: "AppwinNotifications", targets: ["AppwinNotifications"]),
    .library(name: "AppwinAnalytics", targets: ["AppwinAnalytics"]),
    .library(name: "AppwinAttribution", targets: ["AppwinAttribution"]),
    .library(name: "AppwinTikTokEvents", targets: ["AppwinTikTokEvents"]),
  ],
  // Zero external dependencies since ADR-0028 - with ONE deliberate
  // exception (ADR-0038, acted 2026-09-05): the optional AppwinTikTokEvents
  // product wraps the TikTok App Events SDK as an internal adapter.
  // Only apps that add that product link it; the other products stay
  // dependency-free.
  dependencies: [
    .package(
      url: "https://github.com/tiktok/tiktok-business-ios-sdk",
      from: "1.7.2"
    )
  ],
  targets: [
    .target(name: "AppwinCore"),
    .testTarget(name: "AppwinCoreTests", dependencies: ["AppwinCore"]),

    .target(
      name: "AppwinSupport",
      dependencies: ["AppwinCore"],
      resources: [.process("Resources")]
    ),
    .testTarget(name: "AppwinSupportTests", dependencies: ["AppwinSupport"]),

    .target(
      name: "AppwinCommunity",
      dependencies: ["AppwinCore"],
      resources: [.process("Resources")]
    ),
    .testTarget(name: "AppwinCommunityTests", dependencies: ["AppwinCommunity"]),

    .target(
      name: "AppwinNotifications",
      dependencies: ["AppwinCore"],
      resources: [.process("Resources")]
    ),
    .testTarget(name: "AppwinNotificationsTests", dependencies: ["AppwinNotifications"]),

    .target(name: "AppwinAnalytics", dependencies: ["AppwinCore"]),
    .testTarget(name: "AppwinAnalyticsTests", dependencies: ["AppwinAnalytics"]),

    .target(name: "AppwinAttribution", dependencies: ["AppwinCore"]),

    .target(
      name: "AppwinTikTokEvents",
      dependencies: [
        "AppwinCore",
        .product(name: "TikTokBusinessSDK", package: "tiktok-business-ios-sdk"),
      ]
    ),
  ],
  swiftLanguageModes: [.v6]
)
