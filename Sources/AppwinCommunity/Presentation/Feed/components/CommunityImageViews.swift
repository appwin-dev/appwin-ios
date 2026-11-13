import SwiftUI
import UIKit

/// Full-screen image viewer for public community media URLs.
/// Pinch / double-tap zoom; drag-down dismisses only when not zoomed (scale == 1).
struct CommunityImageViewer: View {
    let url: URL

    @Environment(\.dismiss) private var dismiss

    @State private var scale: CGFloat = 1
    @State private var dragOffset: CGSize = .zero

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()

            AsyncImage(url: url) { phase in
                switch phase {
                case .success(let image):
                    image
                        .resizable()
                        .scaledToFit()
                        .scaleEffect(scale)
                        .offset(dragOffset)
                        .gesture(magnification)
                        .gesture(dragToDismiss)
                        .onTapGesture(count: 2) { toggleZoom() }
                case .failure:
                    Image(systemName: "photo")
                        .font(.system(size: 40))
                        .foregroundStyle(.white.opacity(0.5))
                default:
                    ProgressView().tint(.white)
                }
            }

            closeButton
        }
        // Fade while dragging down so dismiss feels like Support's ImageViewerView.
        // Typed: CGFloat / literal is ambiguous for Swift 6.2 (Xcode 26), which refuses to pick.
        .opacity(1 - min(Double(abs(dragOffset.height)) / 400, 0.6))
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
                .accessibilityLabel(CommunityStrings.close)
                .padding()
            }
            Spacer()
        }
    }

    private var magnification: some Gesture {
        MagnificationGesture()
            .onChanged { scale = max(1, $0) }
            .onEnded { _ in
                withAnimation(.spring) {
                    if scale < 1.2 { scale = 1 }
                }
            }
    }

    /// Active only at scale 1 so a zoomed image can still pan via magnification.
    private var dragToDismiss: some Gesture {
        DragGesture()
            .onChanged { if scale == 1 { dragOffset = $0.translation } }
            .onEnded { value in
                if scale == 1, abs(value.translation.height) > 120 {
                    dismiss()
                } else {
                    withAnimation(.spring) { dragOffset = .zero }
                }
            }
    }

    private func toggleZoom() {
        withAnimation(.spring) { scale = scale > 1 ? 1 : 2.5 }
    }
}

/// In-memory cache of feed images keyed by URL, bounded by decoded size.
@MainActor
enum CommunityMediaImageCache {
    private static let cache: NSCache<NSString, UIImage> = {
        let cache = NSCache<NSString, UIImage>()
        cache.totalCostLimit = 64 * 1024 * 1024
        return cache
    }()

    static func image(for url: URL) -> UIImage? {
        cache.object(forKey: url.absoluteString as NSString)
    }

    static func store(_ image: UIImage, for url: URL) {
        let pixels = image.size.width * image.scale * image.size.height * image.scale
        cache.setObject(image, forKey: url.absoluteString as NSString, cost: Int(pixels) * 4)
    }
}

/// Thumbnail that opens [CommunityImageViewer] on tap.
///
/// Not `AsyncImage`: in the lazy feed it reports a download cancelled by a
/// scroll as `.failure` and never retries, so a valid image stayed a grey
/// placeholder until opened. Here a cancelled load just restarts on the next
/// appearance, and a failed one is retried before giving up.
///
/// Tap via `onTapGesture` (not `Button`): a Button + `scaledToFill` label
/// expands the hit target past the clipped frame and steals taps meant for
/// the stats row / comment action below the image on PostCard.
struct CommunityTappableImage: View {
    let url: URL
    var alt: String? = nil

    private enum LoadState {
        case loading
        case loaded(UIImage)
        case failed
    }

    @Environment(\.communityTheme) private var theme
    @State private var isPresentingViewer = false
    @State private var state: LoadState = .loading

    var body: some View {
        Group {
            switch state {
            case .loaded(let image):
                Image(uiImage: image)
                    .resizable()
                    .scaledToFill()
            case .failed:
                theme.colors.border.overlay(
                    Image(systemName: "photo")
                        .foregroundStyle(theme.colors.textTertiary)
                )
            case .loading:
                theme.colors.border.opacity(0.4)
            }
        }
        .task(id: url) { await load() }
        // Expand into the parent frame (single-media 4:5 cap or square grid).
        .frame(minWidth: 0, maxWidth: .infinity, minHeight: 0, maxHeight: .infinity)
        .clipped()
        .contentShape(Rectangle())
        .onTapGesture { isPresentingViewer = true }
        .fullScreenCover(isPresented: $isPresentingViewer) {
            CommunityImageViewer(url: url)
        }
        .accessibilityLabel(alt ?? "")
        .accessibilityAddTraits(.isButton)
    }

    @MainActor
    private func load() async {
        if let cached = CommunityMediaImageCache.image(for: url) {
            state = .loaded(cached)
            return
        }
        if case .loaded = state {} else { state = .loading }
        for attempt in 1...3 {
            if let (data, response) = try? await URLSession.shared.data(from: url),
               let http = response as? HTTPURLResponse,
               (200..<300).contains(http.statusCode),
               let image = UIImage(data: data) {
                CommunityMediaImageCache.store(image, for: url)
                state = .loaded(image)
                return
            }
            // Cancelled: the cell left the screen, and the next appearance
            // starts a fresh load. Never shown as a failure.
            if Task.isCancelled { return }
            if attempt < 3 {
                try? await Task.sleep(nanoseconds: UInt64(attempt) * 600_000_000)
                if Task.isCancelled { return }
            }
        }
        state = .failed
    }
}
