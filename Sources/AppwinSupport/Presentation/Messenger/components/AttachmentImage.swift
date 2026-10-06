// Attachment image loader with a shared memory cache keyed by attachment id.
// The image downloaded for the list thumbnail is reused as-is in the full-screen
// viewer, so tapping costs no network. Replaces independent `AsyncImage`s, which
// cache per instance and re-downloaded on every view. Re-signs the URL once if
// it has expired.

import SwiftUI
import UIKit

/// Memory cache of decoded images, keyed by `attachment.id`, which stays stable
/// when the URL is re-signed. `@MainActor` makes the global state safe.
@MainActor
final class AttachmentImageCache {
    static let shared = AttachmentImageCache()
    private let cache = NSCache<NSString, UIImage>()

    func image(for id: String) -> UIImage? { cache.object(forKey: id as NSString) }
    func store(_ image: UIImage, for id: String) { cache.setObject(image, forKey: id as NSString) }
}

struct AttachmentImage<Content: View, Placeholder: View>: View {
    let attachment: Attachment
    @ViewBuilder var content: (Image) -> Content
    @ViewBuilder var placeholder: () -> Placeholder

    @EnvironmentObject private var messageStore: MessageStore
    @State private var uiImage: UIImage?
    @State private var didRetry = false

    var body: some View {
        Group {
            if let uiImage {
                content(Image(uiImage: uiImage))
            } else {
                placeholder()
            }
        }
        .task { await load() }
    }

    @MainActor
    private func load() async {
        if uiImage != nil { return }
        // Already cached by the thumbnail: instant, no network.
        if let cached = AttachmentImageCache.shared.image(for: attachment.id) {
            uiImage = cached
            return
        }
        // Otherwise download; on failure the URL may have expired, so re-sign
        // once and retry.
        if await download(from: attachment.url) { return }
        guard !didRetry else { return }
        didRetry = true
        if let fresh = try? await messageStore.freshAttachmentURL(attachmentId: attachment.id) {
            _ = await download(from: fresh)
        }
    }

    /// Downloads, decodes and caches. `false` when the URL failed - network or
    /// non-2xx, typically an expired presign - which triggers the re-sign.
    @MainActor
    private func download(from url: URL) async -> Bool {
        guard
            let (data, response) = try? await URLSession.shared.data(from: url),
            let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode),
            let img = UIImage(data: data)
        else { return false }
        AttachmentImageCache.shared.store(img, for: attachment.id)
        uiImage = img
        return true
    }
}
