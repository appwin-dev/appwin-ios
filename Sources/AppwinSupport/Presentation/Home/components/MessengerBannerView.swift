// 1:1 port of `messenger-banner.tsx` (Figma BannerForSupport 441:6615).
// PNG assets bundled in the SDK; no remote SVG.

import SwiftUI
import UIKit

struct MessengerBannerView: View {
    let design: MessengerDesign
    let accent: Color
    /// `#RRGGBB` for darkenHex on the photo preset. Optional: without it the
    /// derived shade is impossible, so the accent is used.
    var accentHex: String? = nil

    /// Figma `support-banner` 447:5969 - 280x91 (ratio ~3.077).
    private static let bannerAspect: CGFloat = 280 / 91

    var body: some View {
        // Fixed frame before the content: stops a custom photo from blowing up
        // the height inside the ScrollView through its intrinsic size.
        Color.clear
            .frame(maxWidth: .infinity)
            .aspectRatio(Self.bannerAspect, contentMode: .fit)
            .overlay {
                bannerContent
            }
            .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
    }

    @ViewBuilder
    private var bannerContent: some View {
        if design.bannerSource == .none {
            EmptyView()
        } else if design.bannerSource == .custom, let url = design.bannerUrl {
            CustomBannerImage(url: url, accent: accent, focusY: design.bannerFocusY)
        } else {
            BannerArt(presetId: design.presetBannerId, brand: accent, brandHex: accentHex)
        }
    }
}

// MARK: - Banner art (switch presets)

private struct BannerArt: View {
    let presetId: MessengerPresetBannerId
    let brand: Color
    let brandHex: String?

    var body: some View {
        switch presetId {
        case .emojis:
            EmojisBanner(brand: brand)
        case .amicale:
            AmicaleBanner(brand: brand)
        case .discret:
            DiscretBanner()
        case .photo:
            PhotoBanner(brand: brand, brandHex: brandHex)
        case .icon:
            IconBanner(brand: brand)
        case .serious:
            SeriousBanner()
        }
    }
}

// MARK: - Inset helper (%, matching CSS top/right/bottom/left)

private struct PercentInset {
    let top: CGFloat
    let right: CGFloat
    let bottom: CGFloat
    let left: CGFloat

    func rect(in size: CGSize) -> CGRect {
        let t = size.height * top / 100
        let r = size.width * right / 100
        let b = size.height * bottom / 100
        let l = size.width * left / 100
        return CGRect(
            x: l,
            y: t,
            width: size.width - l - r,
            height: size.height - t - b
        )
    }
}

private struct InsetFrame<Content: View>: View {
    let inset: PercentInset
    @ViewBuilder let content: () -> Content

    var body: some View {
        GeometryReader { geo in
            let rect = inset.rect(in: geo.size)
            content()
                .frame(width: max(0, rect.width), height: max(0, rect.height))
                .position(x: rect.midX, y: rect.midY)
        }
    }
}

// MARK: - Emoji (Figma 441:7565) - EMOJI_TILES 1:1

private enum EmojiTileKind {
    case a, b, wave, laptop, lifebuoy, empty

    var asset: BannerAsset? {
        switch self {
        case .a: return .tileA
        case .b: return .tileB
        case .wave: return .emojiWave
        case .laptop: return .emojiLaptop
        case .lifebuoy: return .emojiLifebuoy
        case .empty: return nil
        }
    }

    var isEmoji: Bool {
        switch self {
        case .wave, .laptop, .lifebuoy: return true
        default: return false
        }
    }
}

private struct EmojiTile {
    let inset: PercentInset
    let kind: EmojiTileKind
}

/// Same table as `EMOJI_TILES` in messenger-banner.tsx.
private let emojiTiles: [EmojiTile] = [
    // row 1
    .init(inset: .init(top: 1.24, right: 88.08, bottom: 52.42, left: -3.14), kind: .a),
    .init(inset: .init(top: -5.04, right: 73.56, bottom: 58.7, left: 11.38), kind: .b),
    .init(inset: .init(top: -11.32, right: 59.04, bottom: 64.98, left: 25.91), kind: .a),
    .init(inset: .init(top: -17.6, right: 44.51, bottom: 71.26, left: 40.43), kind: .a),
    .init(inset: .init(top: -23.88, right: 29.99, bottom: 77.55, left: 54.95), kind: .a),
    .init(inset: .init(top: -30.16, right: 15.46, bottom: 83.83, left: 69.48), kind: .b),
    .init(inset: .init(top: -36.44, right: 0.94, bottom: 90.11, left: 84), kind: .a),
    // row 2
    .init(inset: .init(top: 45.93, right: 86.04, bottom: 7.73, left: -1.1), kind: .a),
    .init(inset: .init(top: 39.65, right: 71.52, bottom: 14.01, left: 13.42), kind: .b),
    .init(inset: .init(top: 33.37, right: 56.99, bottom: 20.29, left: 27.95), kind: .wave),
    .init(inset: .init(top: 27.09, right: 42.47, bottom: 26.58, left: 42.47), kind: .laptop),
    .init(inset: .init(top: 20.81, right: 27.95, bottom: 32.86, left: 56.99), kind: .lifebuoy),
    .init(inset: .init(top: 14.53, right: 13.42, bottom: 39.14, left: 71.52), kind: .b),
    .init(inset: .init(top: 8.25, right: -1.1, bottom: 45.42, left: 86.04), kind: .a),
    // row 3
    .init(inset: .init(top: 90.62, right: 84, bottom: -36.96, left: 0.94), kind: .a),
    .init(inset: .init(top: 84.34, right: 69.48, bottom: -30.67, left: 15.46), kind: .b),
    .init(inset: .init(top: 78.06, right: 54.95, bottom: -24.39, left: 29.99), kind: .a),
    .init(inset: .init(top: 71.78, right: 40.43, bottom: -18.11, left: 44.51), kind: .a),
    .init(inset: .init(top: 65.5, right: 25.91, bottom: -11.83, left: 59.04), kind: .empty),
    .init(inset: .init(top: 59.22, right: 11.38, bottom: -5.55, left: 73.56), kind: .b),
    .init(inset: .init(top: 52.94, right: -3.14, bottom: 0.73, left: 88.08), kind: .a),
]

private struct EmojisBanner: View {
    let brand: Color

    var body: some View {
        GeometryReader { geo in
            ZStack {
                brand
                ForEach(Array(emojiTiles.enumerated()), id: \.offset) { _, tile in
                    let cell = tile.inset.rect(in: geo.size)
                    EmojiTileView(kind: tile.kind, cell: cell)
                        .frame(width: max(0, cell.width), height: max(0, cell.height))
                        .position(x: cell.midX, y: cell.midY)
                }
            }
        }
    }
}

/// Tile cell - `hypot(87.6777cqw, 12.3223cqh)` plus rotate(-8deg), as in CSS.
private struct EmojiTileView: View {
    let kind: EmojiTileKind
    let cell: CGRect

    var body: some View {
        let w = hypot(0.876777 * cell.width, 0.123223 * cell.height)
        let h = hypot(0.123223 * cell.width, 0.876777 * cell.height)
        ZStack {
            if let asset = kind.asset {
                asset.image
                    .resizable()
                    .aspectRatio(contentMode: kind.isEmoji ? .fill : .fit)
                    .frame(width: w, height: h)
                    .clipped()
            } else {
                RoundedRectangle(cornerRadius: 20, style: .continuous)
                    .fill(Color.white.opacity(0.05))
                    .frame(width: w, height: h)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .rotationEffect(.degrees(-8))
    }
}

// MARK: - Friendly (441:6614)

private struct AmicaleBanner: View {
    let brand: Color

    var body: some View {
        ZStack {
            // linear-gradient white 20% + brand
            brand
            Color.white.opacity(0.2)
            InsetFrame(inset: .init(top: -14.87, right: 22.83, bottom: -15.38, left: 22.83)) {
                BannerAsset.amicale.image
                    .resizable()
                    .scaledToFill()
            }
        }
    }
}

// MARK: - Discreet (441:7515)

private struct DiscretBanner: View {
    private let slate200 = Color(red: 226 / 255, green: 232 / 255, blue: 240 / 255)

    var body: some View {
        ZStack {
            slate200
            InsetFrame(inset: .init(top: -15.9, right: 16.67, bottom: -89.23, left: 16.67)) {
                BannerAsset.discret.image
                    .resizable()
                    .scaledToFill()
            }
        }
    }
}

// MARK: - Photo (441:6616)

private struct PhotoBanner: View {
    let brand: Color
    let brandHex: String?

    var body: some View {
        GeometryReader { geo in
            let dark = brandHex.flatMap { parseHexColor(darkenHex($0, amount: 0.45)) } ?? brand.opacity(0.55)
            // top -260.51%, bottom -101.03%, aspect 500/750, centred
            let top = geo.size.height * (-260.51 / 100)
            let bottom = geo.size.height * (-101.03 / 100)
            let imgH = geo.size.height - top - bottom
            let imgW = imgH * (500.0 / 750.0)
            ZStack {
                dark
                BannerAsset.photo.image
                    .resizable()
                    .scaledToFill()
                    .frame(width: imgW, height: imgH)
                    .clipped()
                    .position(x: geo.size.width / 2, y: top + imgH / 2)
                brand.opacity(0.8)
            }
        }
    }
}

// MARK: - Icon (441:7957) - 5 layers

private struct IconBanner: View {
    let brand: Color

    var body: some View {
        ZStack {
            brand
            InsetFrame(inset: .init(top: -71.28, right: 10, bottom: -74.87, left: 10)) {
                BannerAsset.iconRingOuter.image.resizable().scaledToFill()
            }
            InsetFrame(inset: .init(top: -40.51, right: 20, bottom: -44.1, left: 20)) {
                BannerAsset.iconRingMid.image.resizable().scaledToFill()
            }
            InsetFrame(inset: .init(top: -9.74, right: 30, bottom: -13.33, left: 30)) {
                BannerAsset.iconRingInner.image.resizable().scaledToFill()
            }
            // Headset and mic zone: bottom 24.1%, top 24.62%, centred square
            GeometryReader { geo in
                let top = geo.size.height * 0.2462
                let bottom = geo.size.height * 0.241
                let side = geo.size.height - top - bottom
                ZStack {
                    InsetFrame(inset: .init(top: 12.5, right: 12.5, bottom: 12.5, left: 12.5)) {
                        BannerAsset.iconHeadset.image.resizable().scaledToFit()
                    }
                    InsetFrame(inset: .init(top: 64.64, right: 39.64, bottom: 27.08, left: 39.64)) {
                        BannerAsset.iconMic.image.resizable().scaledToFit()
                    }
                }
                .frame(width: side, height: side)
                .clipped()
                .position(x: geo.size.width / 2, y: top + side / 2)
            }
        }
    }
}

// MARK: - Serious (441:7404)

private struct SeriousBanner: View {
    private let slate200 = Color(red: 226 / 255, green: 232 / 255, blue: 240 / 255)

    var body: some View {
        ZStack {
            slate200
            InsetFrame(inset: .init(top: -21.54, right: 19.67, bottom: -65.13, left: 19.67)) {
                BannerAsset.serious.image
                    .resizable()
                    .scaledToFill()
            }
        }
    }
}

// MARK: - Custom banner (user URL; remote PNG/JPEG is fine)

private struct CustomBannerImage: View {
    let url: URL
    let accent: Color
    var focusY: Double = 50

    @State private var uiImage: UIImage?

    var body: some View {
        GeometryReader { geo in
            Group {
                if let uiImage {
                    Image(uiImage: uiImage)
                        .resizable()
                        .scaledToFill()
                        .frame(width: geo.size.width, height: geo.size.height, alignment: .top)
                        .offset(y: verticalOffset(image: uiImage, in: geo.size))
                } else {
                    accent
                }
            }
            .frame(width: geo.size.width, height: geo.size.height)
            .clipped()
        }
        // Fills the parent frame only (280x91 aspect); it does not offer its
        // own intrinsic size.
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .task(id: url.absoluteString) {
            await loadImage()
        }
    }

    private func verticalOffset(image: UIImage, in frame: CGSize) -> CGFloat {
        let imgW = image.size.width
        let imgH = image.size.height
        guard imgW > 0, imgH > 0, frame.width > 0, frame.height > 0 else { return 0 }
        let imgAspect = imgW / imgH
        let frameAspect = frame.width / frame.height
        // When the image is wider than the frame, no vertical panning.
        guard imgAspect < frameAspect else { return 0 }
        let scaledHeight = frame.width / imgAspect
        let excess = max(0, scaledHeight - frame.height)
        let t = CGFloat(min(100, max(0, focusY)) / 100)
        return -excess * t
    }

    private func loadImage() async {
        do {
            let (data, _) = try await URLSession.shared.data(from: url)
            if let image = UIImage(data: data) {
                uiImage = image
            }
        } catch {
            uiImage = nil
        }
    }
}
