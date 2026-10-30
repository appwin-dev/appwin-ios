import Foundation
import MachO

/// A loaded Mach-O image: what an absolute address needs to be resolved to a
/// module now, and to a dSYM later (`debugImages`, ADR-0056 phase 3).
struct BinaryImage: Sendable, Equatable, Codable {
  /// File name, not the path: the path embeds the install's container UUID.
  let name: String
  /// Load address of the Mach-O header, ASLR slide included.
  let addr: UInt64
  /// `__TEXT` size: `[addr, addr + size)` is the code a frame can point into.
  let size: UInt64
  /// `LC_UUID`, the key dSYMs are filed under.
  let debugId: String
  let isMainExecutable: Bool

  func contains(_ address: UInt64) -> Bool {
    address >= addr && address < addr &+ size
  }
}

enum BinaryImages {
  /// Images loaded right now. Images loaded after this call (a late
  /// `dlopen`) are missing from a snapshot taken earlier.
  static func loaded() -> [BinaryImage] {
    var images: [BinaryImage] = []
    let count = _dyld_image_count()
    images.reserveCapacity(Int(count))
    for index in 0..<count {
      guard let header = _dyld_get_image_header(index), let cName = _dyld_get_image_name(index)
      else { continue }
      if let image = image(header: header, path: String(cString: cName)) { images.append(image) }
    }
    return images
  }

  static func image(containing address: UInt64, in images: [BinaryImage]) -> BinaryImage? {
    images.first { $0.contains(address) }
  }

  private static func image(header: UnsafePointer<mach_header>, path: String) -> BinaryImage? {
    // iOS has been 64-bit only since iOS 11.
    guard header.pointee.magic == MH_MAGIC_64 else { return nil }
    var uuid: String?
    var textSize: UInt64 = 0
    var command = UnsafeRawPointer(header).advanced(by: MemoryLayout<mach_header_64>.size)
    for _ in 0..<header.pointee.ncmds {
      let load = command.load(as: load_command.self)
      if load.cmd == LC_UUID {
        let uuidCommand = command.load(as: uuid_command.self)
        uuid = UUID(uuid: uuidCommand.uuid).uuidString.lowercased()
      } else if load.cmd == UInt32(LC_SEGMENT_64) {
        let segment = command.load(as: segment_command_64.self)
        let name = withUnsafeBytes(of: segment.segname) { raw in
          String(decoding: raw.prefix { $0 != 0 }, as: UTF8.self)
        }
        if name == SEG_TEXT { textSize = segment.vmsize }
      }
      command = command.advanced(by: Int(load.cmdsize))
    }
    guard let uuid, textSize > 0 else { return nil }
    return BinaryImage(
      name: (path as NSString).lastPathComponent,
      addr: UInt64(UInt(bitPattern: header)),
      size: textSize,
      debugId: uuid,
      isMainExecutable: header.pointee.filetype == UInt32(MH_EXECUTE))
  }
}

/// Decides which frames are the studio's own code, the only ones feeding the
/// issue fingerprint server-side: the main executable, plus the frameworks
/// the studio lists as its own (`inAppModules`).
struct InAppModules: Sendable {
  private let extra: Set<String>

  init(_ modules: [String]) {
    extra = Set(modules.filter { !$0.isEmpty })
  }

  /// Statically linked (SwiftPM), the SDK lives inside the main executable:
  /// a symbol naming one of its modules is taken out. Without symbols (a
  /// signal crash) there is no telling, the frame stays in-app.
  private static let sdkModules = [
    "AppwinCore.", "AppwinAnalytics.", "AppwinSupport.", "AppwinCommunity.",
    "AppwinNotifications.", "AppwinAttribution.", "AppwinTikTokEvents.",
  ]

  func isInApp(image: BinaryImage?, symbol: String) -> Bool {
    guard let image else { return false }
    guard image.isMainExecutable || extra.contains(image.name) else { return false }
    return !Self.sdkModules.contains { symbol.contains($0) }
  }
}

enum CrashFrames {
  /// Frames for addresses captured in this process: modules from the live
  /// image list, symbols from `dladdr` when the binary still has them.
  static func live(
    addresses: [UInt64], images: [BinaryImage], inApp: InAppModules
  ) -> [CrashReport.Frame] {
    addresses.prefix(CrashReport.maxFrames).map { address in
      let image = BinaryImages.image(containing: address, in: images)
      let symbol = symbolName(address)
      return CrashReport.Frame(
        fn: symbol, module: image?.name, addr: address,
        inApp: inApp.isInApp(image: image, symbol: symbol))
    }
  }

  /// Frames for addresses of a previous process: no symbols (the images
  /// moved), modules from the image list saved by that process.
  static func offline(
    addresses: [UInt64], images: [BinaryImage], inApp: InAppModules
  ) -> [CrashReport.Frame] {
    addresses.prefix(CrashReport.maxFrames).map { address in
      let image = BinaryImages.image(containing: address, in: images)
      return CrashReport.Frame(
        fn: "", module: image?.name, addr: address, inApp: inApp.isInApp(image: image, symbol: ""))
    }
  }

  /// The images the frames point into, for symbolication.
  static func referencedImages(
    _ frames: [CrashReport.Frame], images: [BinaryImage]
  ) -> [BinaryImage] {
    let names = Set(frames.compactMap(\.module))
    return images.filter { names.contains($0.name) }
  }

  private static func symbolName(_ address: UInt64) -> String {
    var info = Dl_info()
    guard let pointer = UnsafeRawPointer(bitPattern: UInt(address)),
          dladdr(pointer, &info) != 0, let cName = info.dli_sname
    else { return "" }
    let raw = String(cString: cName)
    // A stripped executable resolves every address to its header symbol:
    // a constant wrong name would fold every crash into one issue.
    if raw == "_mh_execute_header" || raw == "<redacted>" { return "" }
    return demangle(raw) ?? raw
  }

  private typealias DemangleFunction = @convention(c) (
    UnsafePointer<CChar>?, Int, UnsafeMutablePointer<CChar>?, UnsafeMutablePointer<Int>?, UInt32
  ) -> UnsafeMutablePointer<CChar>?

  /// `swift_demangle` is exported by the Swift runtime but not declared in
  /// any header.
  private static let demangler: DemangleFunction? = {
    guard let symbol = dlsym(UnsafeMutableRawPointer(bitPattern: -2), "swift_demangle") else {
      return nil
    }
    return unsafeBitCast(symbol, to: DemangleFunction.self)
  }()

  private static func demangle(_ symbol: String) -> String? {
    guard let demangler, symbol.hasPrefix("$s") || symbol.hasPrefix("_$s") else { return nil }
    let mangled = symbol.hasPrefix("_") ? String(symbol.dropFirst()) : symbol
    return mangled.withCString { cString in
      guard let result = demangler(cString, strlen(cString), nil, nil, 0) else { return nil }
      defer { free(result) }
      return String(cString: result)
    }
  }
}
