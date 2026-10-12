import SwiftUI

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
        .opacity(1 - min(abs(dragOffset.height) / 400, 0.6))
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

/// Thumbnail that opens [CommunityImageViewer] on tap.
///
/// Tap via `onTapGesture` (not `Button`): a Button + `scaledToFill` label
/// expands the hit target past the clipped frame and steals taps meant for
/// the stats row / comment action below the image on PostCard.
struct CommunityTappableImage: View {
    let url: URL
    var alt: String? = nil

    @Environment(\.communityTheme) private var theme
    @State private var isPresentingViewer = false

    var body: some View {
        AsyncImage(url: url) { phase in
            switch phase {
            case .success(let image):
                image
                    .resizable()
                    .scaledToFill()
            case .failure:
                theme.colors.border.overlay(
                    Image(systemName: "photo")
                        .foregroundStyle(theme.colors.textTertiary)
                )
            default:
                theme.colors.border.opacity(0.4)
            }
        }
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
}
