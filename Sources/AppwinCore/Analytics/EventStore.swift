import Foundation

/// Disk queue for analytics events. NOT thread-safe on purpose: the
/// EventPipeline actor is the only caller and serializes every access.
///
/// Layout: `current.jsonl` receives appends, one wire-format event per line;
/// at `maxBatch` lines, or when a flush starts, it is atomically renamed to
/// `ready-<ms>-<seq>.jsonl` (zero-padded, so lexical order is rotation
/// order even for two rotations in the same millisecond). One ready file =
/// one POST, deleted on success. JSONL keeps the crash blast radius to the
/// last line, and the rename keeps a half-written batch out of the send path.
final class EventStore {
  struct ReadyBatch {
    let file: URL
    let lines: [String]
  }

  private let directory: URL
  private let maxBatch: Int
  private let maxQueueEvents: Int

  private var currentLineCount = 0
  private var readyLineCounts: [String: Int] = [:]
  private var rotationSeq = 0

  /// Events currently on disk (current + ready). Overflow control input.
  private(set) var queuedEventCount = 0

  private var currentFile: URL { directory.appendingPathComponent("current.jsonl") }

  init(directory: URL, maxBatch: Int, maxQueueEvents: Int) {
    self.directory = directory
    self.maxBatch = maxBatch
    self.maxQueueEvents = maxQueueEvents
  }

  /// Creates the directory and rebuilds the counters from what a previous
  /// launch left behind. Called once, off the main thread.
  func start() {
    do {
      try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
      var values = URLResourceValues()
      values.isExcludedFromBackup = true
      var dir = directory
      try? dir.setResourceValues(values)
    } catch {
      log("analytics store: cannot create \(directory.path): \(error)")
    }
    currentLineCount = lineCount(of: currentFile)
    readyLineCounts = [:]
    for file in readyFiles() {
      readyLineCounts[file.lastPathComponent] = lineCount(of: file)
    }
    recomputeTotal()
  }

  /// Appends one wire-format event line. Returns how many older events were
  /// dropped to stay under `maxQueueEvents` (0 in the nominal case).
  @discardableResult
  func append(_ line: String) -> Int {
    guard let data = (line + "\n").data(using: .utf8) else { return 0 }
    do {
      if !FileManager.default.fileExists(atPath: currentFile.path) {
        try data.write(to: currentFile, options: .atomic)
      } else {
        let handle = try FileHandle(forWritingTo: currentFile)
        defer { try? handle.close() }
        try handle.seekToEnd()
        try handle.write(contentsOf: data)
      }
    } catch {
      log("analytics store: append failed: \(error)")
      return 0
    }
    currentLineCount += 1
    recomputeTotal()
    var dropped = 0
    if currentLineCount >= maxBatch { rotateCurrent() }
    dropped += enforceLimit()
    return dropped
  }

  /// Makes the current file a ready batch (atomic rename). No-op when empty.
  func rotateCurrent() {
    guard currentLineCount > 0 else { return }
    let ms = Int64(Date().timeIntervalSince1970 * 1000)
    let name = String(format: "ready-%013lld-%04d.jsonl", ms, rotationSeq)
    rotationSeq += 1
    do {
      try FileManager.default.moveItem(at: currentFile, to: directory.appendingPathComponent(name))
      readyLineCounts[name] = currentLineCount
      currentLineCount = 0
      recomputeTotal()
    } catch {
      log("analytics store: rotate failed: \(error)")
    }
  }

  /// Oldest ready batch, with corrupt lines dropped individually and fully
  /// unreadable files deleted. Nil when nothing is ready.
  func nextReadyBatch() -> ReadyBatch? {
    for file in readyFiles() {
      guard let content = try? String(contentsOf: file, encoding: .utf8) else {
        log("analytics store: unreadable batch \(file.lastPathComponent), dropping it")
        delete(file: file)
        continue
      }
      let lines = content.split(separator: "\n").map(String.init).filter(isValidEventLine)
      if lines.isEmpty {
        delete(file: file)
        continue
      }
      return ReadyBatch(file: file, lines: lines)
    }
    return nil
  }

  func delete(file: URL) {
    try? FileManager.default.removeItem(at: file)
    readyLineCounts[file.lastPathComponent] = nil
    recomputeTotal()
  }

  /// Consent denied: everything goes.
  func purgeAll() {
    try? FileManager.default.removeItem(at: directory)
    currentLineCount = 0
    readyLineCounts = [:]
    queuedEventCount = 0
    try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
  }

  // MARK: - Internals

  private func readyFiles() -> [URL] {
    let names = (try? FileManager.default.contentsOfDirectory(atPath: directory.path)) ?? []
    return names
      .filter { $0.hasPrefix("ready-") && $0.hasSuffix(".jsonl") }
      .sorted()
      .map { directory.appendingPathComponent($0) }
  }

  private func enforceLimit() -> Int {
    var dropped = 0
    while queuedEventCount > maxQueueEvents {
      guard let oldest = readyFiles().first else { break }
      dropped += readyLineCounts[oldest.lastPathComponent] ?? 0
      log("analytics store: queue over \(maxQueueEvents), dropping \(oldest.lastPathComponent)")
      delete(file: oldest)
    }
    return dropped
  }

  private func isValidEventLine(_ line: String) -> Bool {
    guard let data = line.data(using: .utf8) else { return false }
    return (try? JSONSerialization.jsonObject(with: data)) is [String: Any]
  }

  private func lineCount(of file: URL) -> Int {
    guard let content = try? String(contentsOf: file, encoding: .utf8) else { return 0 }
    return content.split(separator: "\n").count
  }

  private func recomputeTotal() {
    queuedEventCount = currentLineCount + readyLineCounts.values.reduce(0, +)
  }

  private func log(_ message: String) {
    #if DEBUG
    print("[Appwin] \(message)")
    #endif
  }
}
