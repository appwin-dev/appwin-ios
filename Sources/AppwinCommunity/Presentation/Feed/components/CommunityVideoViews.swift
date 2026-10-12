import SwiftUI
import AVKit
import AVFoundation
import UIKit

/// Feed / detail video tile: remote poster plus a centred play control.
/// Community media URLs are public, so there is no re-sign step.
struct CommunityVideoThumbnail: View {
    let media: CommunityMedia

    @Environment(\.communityTheme) private var theme
    @State private var poster: UIImage?
    @State private var isPresentingPlayer = false

    var body: some View {
        // Same pattern as CommunityTappableImage: avoid Button + fill, which
        // leaks hit targets past the clipped media frame into stats/actions.
        ZStack {
            posterLayer
            Color.black.opacity(0.12)
            playButton
        }
        .frame(minWidth: 0, maxWidth: .infinity, minHeight: 0, maxHeight: .infinity)
        .clipped()
        .contentShape(Rectangle())
        .onTapGesture { isPresentingPlayer = true }
        .task(id: media.url) {
            poster = await Self.loadPoster(url: media.url)
        }
        .fullScreenCover(isPresented: $isPresentingPlayer) {
            CommunityVideoPlayer(url: media.url)
        }
        .accessibilityLabel(media.alt ?? CommunityStrings.addVideo)
        .accessibilityAddTraits(.isButton)
    }

    @ViewBuilder
    private var posterLayer: some View {
        if let poster {
            Image(uiImage: poster)
                .resizable()
                .scaledToFill()
        } else {
            theme.colors.border.opacity(0.4)
            ProgressView()
        }
    }

    private var playButton: some View {
        ZStack {
            Circle()
                .fill(Color.white.opacity(0.35))
                .frame(width: 56, height: 56)
            Image(systemName: "play.fill")
                .font(.system(size: 20, weight: .semibold))
                .foregroundStyle(.white)
                .offset(x: 2)
                .shadow(color: .black.opacity(0.25), radius: 2, y: 1)
        }
    }

    private static func loadPoster(url: URL) async -> UIImage? {
        let gen = AVAssetImageGenerator(asset: AVURLAsset(url: url))
        gen.appliesPreferredTrackTransform = true
        let time = CMTime(seconds: 0.1, preferredTimescale: 600)
        guard let cg = try? await gen.image(at: time).image else { return nil }
        return UIImage(cgImage: cg)
    }
}

/// Full-screen AVKit player for a public community video URL.
struct CommunityVideoPlayer: View {
    let url: URL

    @Environment(\.dismiss) private var dismiss
    @State private var player: AVPlayer?

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()

            if let player {
                VideoPlayer(player: player)
                    .ignoresSafeArea()
            } else {
                ProgressView().tint(.white)
            }

            closeButton
        }
        .task {
            let avPlayer = AVPlayer(url: url)
            player = avPlayer
            avPlayer.play()
        }
        .onDisappear {
            player?.pause()
            player = nil
        }
    }

    private var closeButton: some View {
        VStack {
            HStack {
                Spacer()
                Button { dismiss() } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(.white)
                        .padding(12)
                        .background(Color.black.opacity(0.5), in: Circle())
                }
                .padding()
            }
            Spacer()
        }
    }
}
