import Foundation
import UIKit

/// The segment being recorded, kept on disk frame by frame: if the process
/// dies, the next launch encodes what is here, and the seconds before a crash
/// are the ones worth watching (ADR-0057). Never uploaded as such. Not
/// thread-safe: the recorder's I/O queue is its only user.
final class ReplayFrameBuffer: @unchecked Sendable {
  struct Contents {
    let meta: ReplaySegmentMeta
    let frames: [ReplayVideoEncoder.Frame]
  }

  private let directory: URL
  private let fileManager = FileManager.default
  private var metaURL: URL { directory.appendingPathComponent("segment.json") }

  init(directory: URL) {
    self.directory = directory
  }

  /// Rewritten on every frame: touches and screens accumulate in it.
  func write(meta: ReplaySegmentMeta) {
    try? fileManager.createDirectory(at: directory, withIntermediateDirectories: true)
    try? JSONEncoder().encode(meta).write(to: metaURL, options: .atomic)
  }

  func append(_ image: UIImage, offsetMs: Int) {
    guard let jpeg = image.jpegData(compressionQuality: 0.9) else { return }
    try? fileManager.createDirectory(at: directory, withIntermediateDirectories: true)
    try? jpeg.write(to: directory.appendingPathComponent("\(offsetMs).jpg"), options: .atomic)
  }

  /// What the buffer holds, `endedAt` set from the last frame. Nil when it
  /// holds no complete segment.
  func read() -> Contents? {
    guard let data = try? Data(contentsOf: metaURL),
          var meta = try? JSONDecoder().decode(ReplaySegmentMeta.self, from: data),
          let startedAt = try? Date(meta.startedAt, strategy: ReplaySegmentMeta.iso8601)
    else { return nil }
    let files = (try? fileManager.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil)) ?? []
    let entries = files
      .filter { $0.pathExtension == "jpg" }
      .compactMap { url -> (offsetMs: Int, url: URL)? in
        guard let offset = Int(url.deletingPathExtension().lastPathComponent) else { return nil }
        return (offset, url)
      }
      .sorted { $0.offsetMs < $1.offsetMs }
    var frames: [ReplayVideoEncoder.Frame] = []
    var previous: Data?
    for (index, entry) in entries.enumerated() {
      guard let data = try? Data(contentsOf: entry.url) else { continue }
      defer { previous = data }
      // A still screen is one frame the video holds, not ten encoded again:
      // the JPEG of an unchanged frame is byte for byte the same. The last
      // frame stays, it sets where the segment ends.
      if data == previous && index < entries.count - 1 { continue }
      guard let image = UIImage(data: data)?.cgImage else { continue }
      frames.append(ReplayVideoEncoder.Frame(offsetMs: entry.offsetMs, image: image))
    }
    guard let last = frames.last else { return nil }
    meta.endedAt = ReplaySegmentMeta.timestamp(
      startedAt.addingTimeInterval(Double(last.offsetMs) / 1000 + ReplayLimits.frameInterval))
    return Contents(meta: meta, frames: frames)
  }

  func clear() {
    try? fileManager.removeItem(at: directory)
  }
}
