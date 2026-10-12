import Foundation

/// Encoded segments waiting for upload: one `.json` meta next to one `.mp4`,
/// named by enqueue time so the oldest goes first. Bounded in bytes; the
/// oldest segments are dropped past the cap. Not thread-safe: the uploader
/// actor is its only user.
final class ReplayUploadQueue {
  struct Entry: Equatable {
    let meta: URL
    let video: URL
  }

  private let directory: URL
  private let maxBytes: Int
  private let fileManager = FileManager.default

  init(directory: URL, maxBytes: Int = ReplayLimits.queueMaxBytes) {
    self.directory = directory
    self.maxBytes = maxBytes
  }

  /// Moves `video` into the queue. Returns false when the segment could not
  /// be stored (it is then deleted).
  @discardableResult
  func enqueue(meta: ReplaySegmentMeta, video: URL) -> Bool {
    defer { try? fileManager.removeItem(at: video) }
    try? fileManager.createDirectory(at: directory, withIntermediateDirectories: true)
    let stem = String(format: "%013lld-%05d-%@", Int64(Date().timeIntervalSince1970 * 1000), meta.seq,
                      String(UUID().uuidString.prefix(8)))
    let entry = Entry(
      meta: directory.appendingPathComponent(stem + ".json"),
      video: directory.appendingPathComponent(stem + ".mp4"))
    do {
      try fileManager.moveItem(at: video, to: entry.video)
      // Meta last: a pending entry is a meta file, so a crash in between
      // leaves an orphan video that `pending()` sweeps, never a half entry.
      try JSONEncoder().encode(meta).write(to: entry.meta, options: .atomic)
    } catch {
      delete(entry)
      return false
    }
    enforceBound()
    return true
  }

  /// Oldest first. Videos without a meta are removed on the way.
  func pending() -> [Entry] {
    let files = (try? fileManager.contentsOfDirectory(
      at: directory, includingPropertiesForKeys: nil)) ?? []
    let metas = Set(files.filter { $0.pathExtension == "json" }.map { $0.deletingPathExtension().lastPathComponent })
    for video in files where video.pathExtension == "mp4"
      && !metas.contains(video.deletingPathExtension().lastPathComponent) {
      try? fileManager.removeItem(at: video)
    }
    return metas.sorted().map {
      Entry(
        meta: directory.appendingPathComponent($0 + ".json"),
        video: directory.appendingPathComponent($0 + ".mp4"))
    }
  }

  func load(_ entry: Entry) -> (meta: ReplaySegmentMeta, video: Data)? {
    guard let metaData = try? Data(contentsOf: entry.meta),
          let meta = try? JSONDecoder().decode(ReplaySegmentMeta.self, from: metaData),
          let video = try? Data(contentsOf: entry.video)
    else { return nil }
    return (meta, video)
  }

  func delete(_ entry: Entry) {
    try? fileManager.removeItem(at: entry.meta)
    try? fileManager.removeItem(at: entry.video)
  }

  func purgeAll() {
    try? fileManager.removeItem(at: directory)
  }

  var totalBytes: Int {
    let files = (try? fileManager.contentsOfDirectory(
      at: directory, includingPropertiesForKeys: [.fileSizeKey])) ?? []
    return files.reduce(0) { $0 + ((try? $1.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0) }
  }

  private func enforceBound() {
    var entries = pending()
    while totalBytes > maxBytes, !entries.isEmpty {
      delete(entries.removeFirst())
    }
  }
}
