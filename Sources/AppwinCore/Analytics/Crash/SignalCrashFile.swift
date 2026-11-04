import Foundation

/// The files a signal crash spans, in `<analytics>/crash-signal/`:
/// `context.json`, written when the handler is installed (app and device
/// context, image list), and `pending`, written by the handler itself. Both
/// are turned into a regular report on the next launch.
enum SignalCrashFile {
  struct Record: Equatable {
    let signal: Int32
    let timeMs: Int64
    let addresses: [UInt64]
    let context: Data
  }

  /// What the handler cannot compute: frozen at install, which is also when
  /// the crashed process's images were where its addresses point.
  struct Sidecar: Codable, Equatable {
    let context: CrashContext
    let images: [BinaryImage]
  }

  static func pendingURL(in directory: URL) -> URL { directory.appendingPathComponent("pending") }
  static func sidecarURL(in directory: URL) -> URL { directory.appendingPathComponent("context.json") }

  /// Nil for an empty file (no crash) or one that is not a record.
  static func parse(_ data: Data) -> Record? {
    let marker = Data("\nctx\n".utf8)
    let headerEnd = data.range(of: marker)
    let header = String(decoding: data[..<(headerEnd?.lowerBound ?? data.endIndex)], as: UTF8.self)
    let context = headerEnd.map { Data(data[$0.upperBound...]) } ?? Data()
    var lines = header.split(separator: "\n").makeIterator()
    guard lines.next() == "appwin-signal 1" else { return nil }
    var signal: Int32?
    var timeMs: Int64 = 0
    var addresses: [UInt64] = []
    while let line = lines.next() {
      let parts = line.split(separator: " ", maxSplits: 1)
      guard parts.count == 2 else { continue }
      switch parts[0] {
      case "sig": signal = Int32(parts[1])
      case "ms": timeMs = Int64(parts[1]) ?? 0
      case "pc": if let address = UInt64(parts[1], radix: 16) { addresses.append(address) }
      default: break
      }
    }
    guard let signal else { return nil }
    return Record(signal: signal, timeMs: timeMs, addresses: addresses, context: context)
  }

  static func report(
    record: Record, sidecar: Sidecar, inApp: InAppModules, crashId: String = CrashReport.newId()
  ) -> CrashReport {
    let snapshot = SignalCrashContext.decode(record.context)
    let frames = CrashFrames.offline(addresses: record.addresses, images: sidecar.images, inApp: inApp)
    return CrashReport(
      crashId: crashId,
      kind: .crash,
      runtime: "ios",
      occurredAt: record.timeMs > 0
        ? Date(timeIntervalSince1970: Double(record.timeMs) / 1000) : Date(),
      sessionId: snapshot.sessionId,
      screen: snapshot.screen,
      exceptionType: signalName(record.signal),
      exceptionMessage: nil,
      frames: frames,
      context: sidecar.context,
      breadcrumbs: snapshot.breadcrumbs,
      debugImages: CrashFrames.referencedImages(frames, images: sidecar.images))
  }

  static func signalName(_ signal: Int32) -> String {
    switch signal {
    case SIGABRT: return "SIGABRT"
    case SIGSEGV: return "SIGSEGV"
    case SIGBUS: return "SIGBUS"
    case SIGILL: return "SIGILL"
    case SIGTRAP: return "SIGTRAP"
    case SIGFPE: return "SIGFPE"
    default: return "SIG\(signal)"
    }
  }
}

/// Session, screen and breadcrumbs as the handler copies them: JSON
/// prepared by the app ahead of time, refreshed on every breadcrumb.
enum SignalCrashContext {
  struct Snapshot: Equatable {
    var sessionId: String?
    var screen: String?
    var breadcrumbs: [CrashReport.Breadcrumb] = []
  }

  /// Oldest breadcrumbs go first when the snapshot outgrows `capacity`.
  static func encode(_ snapshot: Snapshot, capacity: Int = SignalCrashHandler.contextCapacity) -> Data {
    var crumbs = snapshot.breadcrumbs
    while true {
      var object: [String: Any] = [
        "breadcrumbs": crumbs.map { crumb in
          [
            "at": Int64(crumb.at.timeIntervalSince1970 * 1000),
            "type": crumb.type.rawValue,
            "name": crumb.name,
          ] as [String: Any]
        }
      ]
      if let sessionId = snapshot.sessionId { object["sessionId"] = sessionId }
      if let screen = snapshot.screen { object["screen"] = String(screen.prefix(CrashReport.maxScreen)) }
      let data = (try? JSONSerialization.data(withJSONObject: object)) ?? Data()
      if data.count <= capacity || crumbs.isEmpty { return data.count <= capacity ? data : Data() }
      crumbs.removeFirst()
    }
  }

  /// Best effort: a snapshot torn by a concurrent update yields an empty one.
  static func decode(_ data: Data) -> Snapshot {
    guard !data.isEmpty,
          let object = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any]
    else { return Snapshot() }
    let crumbs = (object["breadcrumbs"] as? [[String: Any]] ?? []).compactMap { raw -> CrashReport.Breadcrumb? in
      guard let at = (raw["at"] as? NSNumber)?.int64Value,
            let type = (raw["type"] as? String).flatMap(CrashReport.Breadcrumb.Kind.init(rawValue:)),
            let name = raw["name"] as? String
      else { return nil }
      return CrashReport.Breadcrumb(at: Date(timeIntervalSince1970: Double(at) / 1000), type: type, name: name)
    }
    return Snapshot(
      sessionId: object["sessionId"] as? String,
      screen: object["screen"] as? String,
      breadcrumbs: crumbs)
  }
}
