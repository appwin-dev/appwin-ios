// Preview thumbnail of a chosen attachment, before sending, shown in the
// `MessengerComposer`. Cropped square: images decode directly, videos get a
// local poster plus a play badge. A ghost and spinner cover the generation.
//
// The poster is local rather than remote because we already hold the bytes in
// memory, so there is no download.

import SwiftUI
import AVKit
import UniformTypeIdentifiers

struct ComposerAttachmentThumbnail: View {
    let attachment: PickedAttachment

    @State private var image: UIImage?

    private var isVideo: Bool { attachment.mimeType.hasPrefix("video/") }
    private var isImage: Bool { attachment.mimeType.hasPrefix("image/") }
    /// Neither image nor video means a generic file (PDF, doc), so no thumbnail.
    private var isFile: Bool { !isVideo && !isImage }

    var body: some View {
        ZStack {
            if let image {
                Image(uiImage: image).resizable().scaledToFill()
                // Dark scrim, so the composer's close button and the play badge
                // stay readable even on a light image.
                Color.black.opacity(0.2)
                if isVideo {
                    SolarIcon(kind: .playCircle, color: .white, size: 22)
                        .shadow(radius: 2)
                }
            } else if isFile {
                // File card: doc icon plus name, otherwise an endless spinner.
                Color.gray.opacity(0.15)
                VStack(spacing: 4) {
                    SolarIcon(kind: .document, color: .secondary, size: 24)
                    Text(attachment.filename)
                        .font(.caption2)
                        .lineLimit(1)
                        .truncationMode(.middle)
                        .padding(.horizontal, 4)
                }
            } else {
                Color.gray.opacity(0.15)        // ghost (média en cours de décodage)
                ProgressView()
            }
        }
        .task(id: attachment.id) {
            if isVideo {
                image = await Self.videoPoster(data: attachment.data, mime: attachment.mimeType)
            } else if isImage {
                image = UIImage(data: attachment.data)
            }
        }
    }

    /// Poster of a local video. `AVAsset` needs a URL, hence the temp file.
    private static func videoPoster(data: Data, mime: String) async -> UIImage? {
        let ext = UTType(mimeType: mime)?.preferredFilenameExtension ?? "mov"
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
            .appendingPathExtension(ext)
        guard (try? data.write(to: url)) != nil else { return nil }
        defer { try? FileManager.default.removeItem(at: url) }
        let gen = AVAssetImageGenerator(asset: AVURLAsset(url: url))
        gen.appliesPreferredTrackTransform = true   // sinon portrait iPhone tourné 90°
        let time = CMTime(seconds: 0.1, preferredTimescale: 600)
        guard let cg = try? await gen.image(at: time).image else { return nil }
        return UIImage(cgImage: cg)
    }
}
