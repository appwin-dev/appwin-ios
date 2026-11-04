//
//  BannerAssets.swift
//  AppwinSupport
//
//  Banner assets bundled in the pod/SPM, rasterised from the dashboard SVGs.
//  No network dependency and no remote SVG.

import SwiftUI
import UIKit

enum BannerAsset: String, CaseIterable {
    case tileA = "tile-a"
    case tileB = "tile-b"
    case emojiWave = "emoji-wave"
    case emojiLaptop = "emoji-laptop"
    case emojiLifebuoy = "emoji-lifebuoy"
    case amicale
    case discret
    case photo
    case serious
    case iconRingOuter = "icon-ring-outer"
    case iconRingMid = "icon-ring-mid"
    case iconRingInner = "icon-ring-inner"
    case iconHeadset = "icon-headset"
    case iconMic = "icon-mic"

    var image: Image {
        if let ui = uiImage {
            return Image(uiImage: ui)
        }
        assertionFailure("Banner asset missing: \(rawValue).png - run scripts/rasterize-banners.mjs")
        return Image(systemName: "photo")
    }

    var uiImage: UIImage? {
        Self.loadPNG(named: rawValue)
    }

    private static func loadPNG(named name: String) -> UIImage? {
        let bundle = resourceBundle
        if let url = bundle.url(forResource: name, withExtension: "png", subdirectory: "Banners")
            ?? bundle.url(forResource: name, withExtension: "png")
        {
            return UIImage(contentsOfFile: url.path)
        }
        return UIImage(named: name, in: bundle, compatibleWith: nil)
            ?? UIImage(named: "Banners/\(name)", in: bundle, compatibleWith: nil)
    }

    private static var resourceBundle: Bundle {
        #if SWIFT_PACKAGE
        return .module
        #else
        return Bundle.appwinSupportResources
        #endif
    }
}

#if !SWIFT_PACKAGE
private final class AppwinSupportBundleToken {}

extension Bundle {
    static let appwinSupportResources: Bundle = {
        let candidates: [URL?] = [
            Bundle(for: AppwinSupportBundleToken.self).resourceURL,
            Bundle.main.resourceURL,
            Bundle.main.bundleURL,
        ]
        for base in candidates.compactMap({ $0 }) {
            let url = base.appendingPathComponent("AppwinSupport.bundle")
            if let bundle = Bundle(url: url) { return bundle }
        }
        return Bundle(for: AppwinSupportBundleToken.self)
    }()
}
#endif
