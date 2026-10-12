// Full-screen image viewer, iMessage style, presented on tapping an
// `ImageBubble`. Black background, pinch and double-tap zoom, drag down to
// dismiss. The image comes through `AttachmentImage`, so one already loaded by
// the thumbnail shows instantly with no re-download.

import SwiftUI

struct ImageViewerView: View {
    let attachment: Attachment

    @Environment(\.dismiss) private var dismiss

    // Zoom (pinch and double-tap) and translation (drag to dismiss).
    @State private var scale: CGFloat = 1
    @State private var dragOffset: CGSize = .zero

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()

            AttachmentImage(attachment: attachment) { image in
                image
                    .resizable()
                    .scaledToFit()
                    .scaleEffect(scale)
                    .offset(dragOffset)
                    .gesture(magnification)
                    .gesture(dragToDismiss)
                    .onTapGesture(count: 2) { toggleZoom() }
            } placeholder: {
                ProgressView().tint(.white)
            }

            closeButton
        }
        // Opacity follows the drag, so the photo fades as it falls.
        .opacity(1 - min(abs(dragOffset.height) / 400, 0.6))
    }

    private var closeButton: some View {
        VStack {
            HStack {
                Spacer()
                Button { dismiss() } label: {
                    SolarIcon(kind: .close, color: .white, size: 16)
                        .padding(12)
                        .background(Color.black.opacity(0.5), in: Circle())
                }
                .padding()
            }
            Spacer()
        }
    }

    // MARK: - Gestures

    private var magnification: some Gesture {
        MagnificationGesture()
            .onChanged { scale = max(1, $0) }
            .onEnded { _ in withAnimation(.spring) { if scale < 1.2 { scale = 1 } } }
    }

    /// Drag down to dismiss, active only at scale 1: when zoomed, dragging pans
    /// the image instead, which is the standard behaviour.
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
