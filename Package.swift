// swift-tools-version: 6.0

import PackageDescription

/*
 One package, four products.

 SPM resolves a git URL to the manifest at the repository root, so a repository
 serves exactly one package. Publishing Core, Support, Community and
 Notifications as four repositories would make a studio add four package URLs
 in Xcode and keep four versions aligned by hand. Declaring them as four
 products of one package costs the studio one URL, and it picks the products it
 imports - the pattern `firebase-ios-sdk` uses for its twenty-odd products.

 The consequence to know: the products depend on each other through targets, not
 through versioned packages, so they ship under a single version. That is
 already the rule for the Android, Flutter and React Native artefacts.
 */
let package = Package(
  name: "Appwin",
  platforms: [
    .iOS(.v16)
  ],
  products: [
    .library(name: "AppwinCore", targets: ["AppwinCore"]),
    .library(name: "AppwinSupport", targets: ["AppwinSupport"]),
    .library(name: "AppwinCommunity", targets: ["AppwinCommunity"]),
    .library(name: "AppwinNotifications", targets: ["AppwinNotifications"]),
    .library(name: "AppwinAnalytics", targets: ["AppwinAnalytics"]),
  ],
  // Zero external dependencies since ADR-0028: realtime runs on a native
  // URLSessionWebSocketTask (RealtimeSocket) and Socket.IO is gone.
  targets: [
    .target(name: "AppwinCore"),
    .testTarget(name: "AppwinCoreTests", dependencies: ["AppwinCore"]),

    .target(
      name: "AppwinSupport",
      dependencies: ["AppwinCore"],
      resources: [.process("Resources")]
    ),
    .testTarget(name: "AppwinSupportTests", dependencies: ["AppwinSupport"]),

    .target(name: "AppwinCommunity", dependencies: ["AppwinCore"]),
    .testTarget(name: "AppwinCommunityTests", dependencies: ["AppwinCommunity"]),

    .target(name: "AppwinNotifications", dependencies: ["AppwinCore"]),
    .testTarget(name: "AppwinNotificationsTests", dependencies: ["AppwinNotifications"]),

    .target(name: "AppwinAnalytics", dependencies: ["AppwinCore"]),
    .testTarget(name: "AppwinAnalyticsTests", dependencies: ["AppwinAnalytics"]),
  ],
  swiftLanguageModes: [.v6]
)
