import Foundation

/// One crash report, shaped after `CrashReportSchema` in `@app-win/contracts`
/// (ADR-0056). The bounds are applied here, at capture: a report the server
/// would reject is a report lost for good.
struct CrashReport: Sendable, Equatable {
  enum Kind: String, Sendable {
    case crash
    case nonFatal = "non_fatal"
    case anr
  }

  struct Frame: Sendable, Equatable {
    var fn: String
    var file: String?
    var line: Int?
    var col: Int?
    var module: String?
    var addr: UInt64?
    var inApp: Bool
  }

  struct Breadcrumb: Sendable, Equatable {
    enum Kind: String, Sendable {
      case screen
      case event
    }

    let at: Date
    let type: Kind
    let name: String
  }

  var crashId: String
  var kind: Kind
  /// `ios`, or `flutter` / `react_native` for bridged errors.
  var runtime: String
  var occurredAt: Date
  var sessionId: String?
  var screen: String?
  var exceptionType: String
  var exceptionMessage: String?
  var frames: [Frame]
  var context: CrashContext
  var breadcrumbs: [Breadcrumb]
  var debugImages: [BinaryImage]

  static let maxFrames = 200
  static let maxMessage = 1024
  static let maxBytes = 256 * 1024
  private static let maxType = 256
  private static let maxFn = 512
  private static let maxModule = 256
  static let maxScreen = 128
  private static let maxVersion = 64
  private static let maxSdkVersion = 32
  private static let maxDebugImages = 500

  private static let iso8601 = Date.ISO8601FormatStyle(includingFractionalSeconds: true)

  static func newId() -> String { UUID().uuidString.lowercased() }

  /// Wire JSON, under the server's size limit. An oversized report loses its
  /// debug images, then most of its frames, rather than being dropped.
  func jsonData() -> Data? {
    for (frameLimit, withImages) in [(Self.maxFrames, true), (Self.maxFrames, false), (50, false)] {
      guard let data = try? JSONSerialization.data(
        withJSONObject: jsonObject(frameLimit: frameLimit, withImages: withImages))
      else { return nil }
      if data.count <= Self.maxBytes { return data }
    }
    return nil
  }

  func jsonObject(frameLimit: Int = maxFrames, withImages: Bool = true) -> [String: Any] {
    var object: [String: Any] = [
      "crashId": crashId,
      "kind": kind.rawValue,
      "runtime": runtime,
      "occurredAt": occurredAt.formatted(Self.iso8601),
      "exception": exceptionObject(),
      "frames": frames.prefix(frameLimit).map(Self.frameObject),
      "app": appObject(),
      "device": [
        "os": String(context.os.prefix(Self.maxVersion)),
        "model": String(context.model.prefix(Self.maxScreen)),
      ],
      "sdkVersion": String(context.sdkVersion.prefix(Self.maxSdkVersion)),
    ]
    if let sessionId { object["sessionId"] = sessionId }
    if let screen { object["screen"] = String(screen.prefix(Self.maxScreen)) }
    if !breadcrumbs.isEmpty {
      object["breadcrumbs"] = breadcrumbs.suffix(Breadcrumbs.capacity).map { crumb in
        [
          "at": crumb.at.formatted(Self.iso8601),
          "type": crumb.type.rawValue,
          "name": String(crumb.name.prefix(Self.maxScreen)),
        ]
      }
    }
    if withImages, !debugImages.isEmpty {
      object["debugImages"] = debugImages.prefix(Self.maxDebugImages).map { image in
        [
          "debugId": String(image.debugId.prefix(64)),
          "name": String(image.name.prefix(Self.maxModule)),
          "addr": Self.hex(image.addr),
          "size": image.size,
        ] as [String: Any]
      }
    }
    return object
  }

  private static func hex(_ value: UInt64) -> String { "0x" + String(value, radix: 16) }

  private func exceptionObject() -> [String: Any] {
    let type = exceptionType.isEmpty ? "Unknown" : exceptionType
    var object: [String: Any] = ["type": String(type.prefix(Self.maxType))]
    if let exceptionMessage { object["message"] = String(exceptionMessage.prefix(Self.maxMessage)) }
    return object
  }

  private func appObject() -> [String: Any] {
    var object: [String: Any] = ["version": String(context.appVersion.prefix(Self.maxVersion))]
    if let build = context.appBuild { object["build"] = String(build.prefix(Self.maxVersion)) }
    return object
  }

  private static func frameObject(_ frame: Frame) -> [String: Any] {
    var object: [String: Any] = ["fn": String(frame.fn.prefix(maxFn)), "inApp": frame.inApp]
    if let file = frame.file { object["file"] = String(file.prefix(maxFn)) }
    if let line = frame.line, line >= 0 { object["line"] = line }
    if let col = frame.col, col >= 0 { object["col"] = col }
    if let module = frame.module { object["module"] = String(module.prefix(maxModule)) }
    if let addr = frame.addr { object["addr"] = hex(addr) }
    return object
  }
}

/// App and device, frozen when the crash happens: the report leaves on the
/// next launch, possibly after an update (ADR-0056).
struct CrashContext: Sendable, Equatable, Codable {
  var appVersion: String
  var appBuild: String?
  /// `iOS 18.1`, the format of the events' device context.
  var os: String
  /// Hardware identifier (`iPhone16,2`), not the marketing name.
  var model: String
  var sdkVersion: String

  static func current(sdkVersion: String) -> CrashContext {
    let info = Bundle.main.infoDictionary
    let version = ProcessInfo.processInfo.operatingSystemVersion
    var os = "iOS \(version.majorVersion).\(version.minorVersion)"
    if version.patchVersion > 0 { os += ".\(version.patchVersion)" }
    return CrashContext(
      appVersion: info?["CFBundleShortVersionString"] as? String ?? "unknown",
      appBuild: info?["CFBundleVersion"] as? String,
      os: os,
      model: modelIdentifier(),
      sdkVersion: sdkVersion)
  }

  private static func modelIdentifier() -> String {
    // The simulator reports the host's architecture (`arm64`) in utsname.
    if let simulated = ProcessInfo.processInfo.environment["SIMULATOR_MODEL_IDENTIFIER"] {
      return simulated
    }
    var system = utsname()
    uname(&system)
    let machine = withUnsafeBytes(of: &system.machine) { raw in
      String(decoding: raw.prefix { $0 != 0 }, as: UTF8.self)
    }
    return machine.isEmpty ? "unknown" : machine
  }
}
