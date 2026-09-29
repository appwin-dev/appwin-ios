
import Foundation
import UIKit
import UniformTypeIdentifiers

@MainActor
final class ComposerStore: ObservableObject {
  @Published var pendingUploads: [PickedAttachment] = []
  /// Confirmed uploads by id, so removing a media removes its input without
  /// ambiguity while `pendingUploads` keeps the display order.
  /// `@Published` because an upload finishing in the background fills this
  /// dictionary, and without it the send button would never re-enable.
  @Published private var confirmedUploads: [PickedAttachment.ID: AttachmentInput] = [:]
  private let uploadAttachmentsUseCase: UploadAttachmentsUseCase

  init(uploadAttachmentsUseCase: UploadAttachmentsUseCase) {
    self.uploadAttachmentsUseCase = uploadAttachmentsUseCase
  }

  /// Ready references, in display order, consumed on Send instead of starting
  /// a fresh upload.
  var readyUploads: [AttachmentInput] { pendingUploads.compactMap { confirmedUploads[$0.id] } }

  /// True while at least one media is still uploading, which keeps the send
  /// button disabled until everything is preloaded.
  var isUploading: Bool { pendingUploads.contains { confirmedUploads[$0.id] == nil } }

  /// Per-media upload progress, fed by the delegate as bytes go out.
  /// `@Published` so the thumbnail redraws on each tick.
  @Published private var progressByID: [PickedAttachment.ID: Double] = [:]

  /// Progress for one media, `0` before it starts.
  func progress(for id: PickedAttachment.ID) -> Double { progressByID[id] ?? 0 }

  /// Low-level append. Every entry - photo, video, file - goes through here,
  /// which is also where preloading starts: the upload begins on add so the
  /// reference is ready before Send is tapped.
  private func addMedia(_ media: PickedAttachment){
    pendingUploads.append(media)
    Task { await preload(media) }
  }
  
  /// Uploads a media immediately and remembers its reference. Failures are
  /// ignored for now; a per-media status would be the refinement.
  private func preload(_ media: PickedAttachment) async {
    do {
      let ref = try await uploadAttachmentsUseCase.execute(
        media: media,
        onProgress: { fraction in
          // The delegate calls from a background queue, so hop to the main
          // actor before mutating observed state.
          Task { @MainActor in self.progressByID[media.id] = fraction }
        }
      )
      print("ref", ref)
      // The media may have been removed during the upload: do not file an
      // orphan reference. The confirmed upload is collected server-side.
      guard pendingUploads.contains(where: { $0.id == media.id }) else { return }
      confirmedUploads[media.id] = ref
    } catch {
      print("preload failed: \(error)")
    }
  }
  
  /// Entry 1: media loaded from the PhotosPicker.
  /// The view unwraps `PhotosPickerItem` into `Data`, which is the picker's
  /// concern; here we do the domain work: images are re-encoded to JPEG so
  /// HEIC and PNG converge on one format, everything else passes through.
  func addMedia(data: Data, utType: UTType?) {
    if utType?.conforms(to: .image) == true {
      if let jpeg = UIImage(data: data)?.jpegData(compressionQuality: 0.8) {
        addMedia(PickedAttachment(
          data: jpeg, mimeType: "image/jpeg", filename: "\(UUID().uuidString).jpg"
        ))
      }
    } else {
      let mime = utType?.preferredMIMEType ?? "application/octet-stream"
      let ext = utType?.preferredFilenameExtension ?? "bin"
      addMedia(PickedAttachment(
        data: data, mimeType: mime, filename: "\(UUID().uuidString).\(ext)"
      ))
    }
  }
  
  /// Entry 2: a file picked from the Files app. The URL is security-scoped, so
  /// access is claimed explicitly for the time it takes to copy the bytes. The
  /// real name and type are kept, with no re-encoding.
  func addFile(at url: URL){
    guard url.startAccessingSecurityScopedResource() else { return }
    defer { url.stopAccessingSecurityScopedResource() }
    guard let data = try? Data(contentsOf: url) else { return }
    let utType = UTType(filenameExtension: url.pathExtension)
    let mime = utType?.preferredMIMEType ?? "application/octet-stream"
    addMedia(PickedAttachment(
      data: data, mimeType: mime, filename: url.lastPathComponent
    ))
  }
  
  
  /// Removes a media from the preview along with its preloaded reference, so a
  /// removed media is never sent.
  func remove(id: PickedAttachment.ID){
    pendingUploads.removeAll { $0.id == id }
    confirmedUploads[id] = nil
    progressByID[id] = nil
  }

  /// Clears the preview after a send, or when leaving the screen.
  func clear(){
    pendingUploads.removeAll()
    confirmedUploads.removeAll()
    progressByID.removeAll()
  }
}
