// Instagram-DM-style video preview: 9:16 portrait, rounded corners, poster with
// a centred play button. Tapping opens the in-app AVKit player.
//
// This file also carries `openFresh`, shared with file attachments: it re-signs
// a fresh URL on tap.

import SwiftUI
import AVKit

struct VideoBubble: View {
    let attachment: Attachment

    @EnvironmentObject private var messageStore: MessageStore

    @State private var isPresentingPlayer = false
    @State private var poster: UIImage?

    /// Instagram-DM width, with a 9:16 height.
    private let previewWidth: CGFloat = 220
    private var previewHeight: CGFloat { previewWidth * 16 / 9 }
    private let cornerRadius: CGFloat = 18

    var body: some View {
        Button {
            isPresentingPlayer = true
        } label: {
            ZStack {
                posterLayer
                Color.black.opacity(0.12)
                playButton
                videoBadge
            }
            .frame(width: previewWidth, height: previewHeight)
            .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
            .contentShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
            .shadow(color: Color.black.opacity(0.08), radius: 8, x: 0, y: 4)
        }
        .buttonStyle(.plain)
        .task(id: attachment.id) {
            let url = (try? await messageStore.freshAttachmentURL(attachmentId: attachment.id))
                ?? attachment.url
            poster = await Self.loadPoster(url: url)
        }
        .fullScreenCover(isPresented: $isPresentingPlayer) {
            VideoPlayerView(attachment: attachment)
                .environmentObject(messageStore)
        }
    }

    @ViewBuilder
    private var posterLayer: some View {
        if let poster {
            Image(uiImage: poster)
                .resizable()
                .scaledToFill()
                .frame(width: previewWidth, height: previewHeight)
        } else {
            AppwinTokens.surfaceInverse
            ProgressView().tint(.white)
        }
    }

    /// Semi-transparent circular play button.
    private var playButton: some View {
        ZStack {
            Circle()
                .fill(Color.white.opacity(0.35))
                .frame(width: 64, height: 64)
            Image(systemName: "play.fill")
                .font(.system(size: 22, weight: .semibold))
                .foregroundColor(.white)
                .offset(x: 2)
                .shadow(color: .black.opacity(0.25), radius: 2, y: 1)
        }
    }

    /// Bottom-left camera badge marking this as a video.
    private var videoBadge: some View {
        VStack {
            Spacer()
            HStack {
                SolarIcon(kind: .videoLibrary, color: .white, size: 14)
                    .padding(6)
                    .background(
                        RoundedRectangle(cornerRadius: 6, style: .continuous)
                            .fill(Color.black.opacity(0.35))
                    )
                Spacer()
            }
            .padding(10)
        }
    }

    /// Remote poster (first frame), best effort.
    private static func loadPoster(url: URL) async -> UIImage? {
        let gen = AVAssetImageGenerator(asset: AVURLAsset(url: url))
        gen.appliesPreferredTrackTransform = true
        let time = CMTime(seconds: 0.1, preferredTimescale: 600)
        guard let cg = try? await gen.image(at: time).image else { return nil }
        return UIImage(cgImage: cg)
    }
}

/// Opens an attachment with a freshly re-signed URL. On network failure it falls
/// back to the stored URL, which is no worse than the previous behaviour.
/// Shared with `FileBubble`, which opens in the browser on tap.
/// `@MainActor` because `openURL` must be called on the main thread.
@MainActor
func openFresh(
    _ attachment: Attachment,
    store: MessageStore,
    _ openURL: OpenURLAction
) async {
    let url = (try? await store.freshAttachmentURL(attachmentId: attachment.id)) ?? attachment.url
    openURL(url)
}
