import Foundation

/// One file per report, `<crashId>.json`, sent on a later launch.
///
/// Blocking POSIX I/O with no lock on purpose: `write` runs on the crashing
/// thread, in the last milliseconds of the process, and must neither hop to
/// another queue nor wait on a lock the sender might hold. A temp file plus
/// `rename` keeps a half-written report out of the send path, and `fsync`
/// gets it to disk before the process is killed.
final class CrashStore: Sendable {
  struct Stored: Sendable {
    let url: URL
    let json: String
  }

  static let maxReports = 20
  private static let suffix = ".json"
  private static let tmpSuffix = ".json.tmp"
  private static let staleTmpInterval: TimeInterval = 60

  let directory: URL
  private let maxReports: Int

  init(directory: URL, maxReports: Int = CrashStore.maxReports) {
    self.directory = directory
    self.maxReports = maxReports
  }

  /// Never throws: a failure here must not mask the crash being reported.
  @discardableResult
  func write(crashId: String, json: Data) -> Bool {
    try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    let tmp = directory.appendingPathComponent(crashId + Self.tmpSuffix).path
    let target = directory.appendingPathComponent(crashId + Self.suffix).path
    let fd = open(tmp, O_WRONLY | O_CREAT | O_TRUNC, 0o600)
    guard fd >= 0 else { return false }
    let written = json.withUnsafeBytes { raw -> Bool in
      guard var cursor = raw.baseAddress else { return false }
      var remaining = raw.count
      while remaining > 0 {
        let count = Darwin.write(fd, cursor, remaining)
        if count <= 0 { return false }
        cursor = cursor.advanced(by: count)
        remaining -= count
      }
      return true
    }
    let synced = fsync(fd) == 0
    close(fd)
    guard written, synced, rename(tmp, target) == 0 else {
      unlink(tmp)
      return false
    }
    enforceCap()
    return true
  }

  /// Oldest first, at most `limit`. Stale temp files are cleaned up.
  func pending(limit: Int, now: Date = Date()) -> [Stored] {
    let files = contents()
    for file in files where file.lastPathComponent.hasSuffix(Self.tmpSuffix) {
      // Only old ones: a recent temp file may be a report being written now.
      if let modified = modificationDate(file), now.timeIntervalSince(modified) > Self.staleTmpInterval {
        try? FileManager.default.removeItem(at: file)
      }
    }
    return reports(files).prefix(limit).compactMap { file in
      guard let data = try? Data(contentsOf: file), !data.isEmpty else {
        try? FileManager.default.removeItem(at: file)
        return nil
      }
      return Stored(url: file, json: String(decoding: data, as: UTF8.self))
    }
  }

  func count() -> Int { reports(contents()).count }

  func delete(_ url: URL) {
    try? FileManager.default.removeItem(at: url)
  }

  func purgeAll() {
    try? FileManager.default.removeItem(at: directory)
  }

  private func enforceCap() {
    let reports = reports(contents())
    guard reports.count > maxReports else { return }
    reports.prefix(reports.count - maxReports).forEach(delete)
  }

  private func contents() -> [URL] {
    (try? FileManager.default.contentsOfDirectory(
      at: directory, includingPropertiesForKeys: [.contentModificationDateKey])) ?? []
  }

  private func reports(_ files: [URL]) -> [URL] {
    let dated: [(url: URL, date: Date)] = files
      .filter { $0.lastPathComponent.hasSuffix(Self.suffix) }
      .map { ($0, modificationDate($0) ?? .distantPast) }
    let sorted = dated.sorted { lhs, rhs in
      if lhs.date != rhs.date { return lhs.date < rhs.date }
      return lhs.url.lastPathComponent < rhs.url.lastPathComponent
    }
    return sorted.map(\.url)
  }

  private func modificationDate(_ url: URL) -> Date? {
    try? url.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate
  }
}
