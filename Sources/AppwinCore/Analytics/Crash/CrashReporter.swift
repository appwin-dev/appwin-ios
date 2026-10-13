import Foundation
import os

/// Crash capture and upload (ADR-0056). Lives next to the event pipeline and
/// shares its consent, but not its queue: a report is written synchronously
/// by the dying thread, where the pipeline's actor would never get a turn.
///
/// Consent: `denied` records nothing and purges the backlog; `unknown`
/// records but never sends; `granted` sends on start, on foreground, on
/// network regained and after a non-fatal.
final class CrashReporter: Sendable {
  let store: CrashStore
  let breadcrumbs: Breadcrumbs
  private let context: CrashContext
  private let inApp: InAppModules
  /// `<analytics>/crash-signal`; nil leaves signals out (tests).
  private let signalDirectory: URL?
  private let storedConsent: @Sendable () -> AnalyticsConsent
  private let sessionId: @Sendable () -> String?
  private let uploader: CrashUploader
  private let now: @Sendable () -> Date

  /// The pipeline persists a consent change on its own actor turn; this
  /// makes the change effective here at once (no report written after a
  /// `denied`, no `granted` flush seeing the stale `unknown`).
  private let consentOverride = OSAllocatedUnfairLock<AnalyticsConsent?>(initialState: nil)

  /// Set once a bridged fatal is on disk: React Native then raises its own
  /// `RCTFatalException` for the same error, which must not count twice.
  private let bridgedFatalRecorded = OSAllocatedUnfairLock(initialState: false)

  init(
    store: CrashStore,
    sender: any CrashSender,
    context: CrashContext,
    inApp: InAppModules,
    signalDirectory: URL?,
    storedConsent: @escaping @Sendable () -> AnalyticsConsent,
    sessionId: @escaping @Sendable () -> String?,
    reauthorize: @escaping @Sendable () async -> Bool,
    breadcrumbs: Breadcrumbs = Breadcrumbs(),
    backoff: Backoff = .ingest,
    now: @escaping @Sendable () -> Date = Date.init
  ) {
    self.store = store
    self.breadcrumbs = breadcrumbs
    self.context = context
    self.inApp = inApp
    self.signalDirectory = signalDirectory
    self.storedConsent = storedConsent
    self.sessionId = sessionId
    self.now = now
    let consentOverride = self.consentOverride
    self.uploader = CrashUploader(
      store: store, sender: sender, reauthorize: reauthorize,
      canSend: { (consentOverride.withLock { $0 } ?? storedConsent()) == .granted },
      backoff: backoff)
  }

  /// Never waits on the lock: read from the crashing thread too.
  var consent: AnalyticsConsent {
    let override = consentOverride.withLockIfAvailable { $0 } ?? nil
    return override ?? storedConsent()
  }

  // MARK: - Lifecycle

  /// Converts the previous run's signal crash, then arms the handlers and
  /// sends the backlog. The conversion must come first: arming truncates
  /// the file the handler writes to.
  @MainActor
  func start() {
    let denied = consent == .denied
    if denied { store.purgeAll() }
    if let signalDirectory {
      if !denied { collectSignalCrash(in: signalDirectory) }
      armSignals(in: signalDirectory)
    }
    ExceptionCrashHandler.install { exception in
      AppwinCore.crashReporter?.onUncaughtException(exception)
    }
    flush()
  }

  // MARK: - Capture

  /// Runs on the crashing thread: synchronous, no task, no waiting lock.
  func onUncaughtException(_ exception: NSException) {
    SignalCrashHandler.markExceptionRecorded()
    guard consent != .denied else { return }
    let alreadyReported = bridgedFatalRecorded.withLockIfAvailable { $0 } ?? false
    if alreadyReported, exception.name.rawValue.hasPrefix("RCTFatalException") { return }
    let addresses = exception.callStackReturnAddresses.map { $0.uint64Value }
    let report = makeReport(
      kind: .crash, runtime: "ios", type: exception.name.rawValue, message: exception.reason,
      liveAddresses: addresses)
    write(report)
  }

  /// Built on the caller's thread, so session and breadcrumbs are those of
  /// the moment of the error; written and sent off it.
  func recordError(_ error: any Error, returnAddresses: [UInt64]) {
    guard consent != .denied else { return }
    let (type, message) = Self.describe(error)
    let report = makeReport(
      kind: .nonFatal, runtime: "ios", type: type, message: message, liveAddresses: returnAddresses)
    Task.detached(priority: .utility) { [self] in
      write(report)
      await uploader.flush()
    }
  }

  /// Written before returning: React Native calls this right before the JS
  /// runtime takes the process down.
  func recordBridged(runtime: String, fatal: Bool, type: String, message: String?, frames: [CrashReport.Frame]) {
    guard consent != .denied else { return }
    var report = makeReport(
      kind: fatal ? .crash : .nonFatal, runtime: runtime, type: type, message: message,
      liveAddresses: [])
    report.frames = Array(frames.prefix(CrashReport.maxFrames))
    write(report)
    if fatal { bridgedFatalRecorded.withLock { $0 = true } }
    flush()
  }

  // MARK: - Context

  func onEvent(_ name: String) {
    breadcrumbs.event(name)
    refreshSignalContext()
  }

  func onScreen(_ name: String) {
    breadcrumbs.screen(name)
    refreshSignalContext()
  }

  func onConsentChanged(_ newValue: AnalyticsConsent) {
    consentOverride.withLock { $0 = newValue }
    SignalCrashHandler.setEnabled(newValue != .denied)
    switch newValue {
    case .denied:
      breadcrumbs.clear()
      Task { [uploader, store] in
        await uploader.cancelRetry()
        store.purgeAll()
      }
    case .granted:
      flush()
    case .unknown:
      break
    }
  }

  func flush(resetBackoff: Bool = false) {
    refreshSignalContext()
    Task { [uploader] in await uploader.flush(resetBackoff: resetBackoff) }
  }

  /// Test seam: waits for the upload instead of firing it.
  func flushNow() async { await uploader.flush() }

  // MARK: - Internals

  private func write(_ report: CrashReport) {
    guard let json = report.jsonData() else { return }
    store.write(crashId: report.crashId, json: json)
  }

  private func makeReport(
    kind: CrashReport.Kind, runtime: String, type: String, message: String?, liveAddresses: [UInt64]
  ) -> CrashReport {
    let crumbs = breadcrumbs.snapshot()
    var frames: [CrashReport.Frame] = []
    var debugImages: [BinaryImage] = []
    if !liveAddresses.isEmpty {
      let images = BinaryImages.loaded()
      frames = CrashFrames.live(addresses: liveAddresses, images: images, inApp: inApp)
      debugImages = CrashFrames.referencedImages(frames, images: images)
    }
    return CrashReport(
      crashId: CrashReport.newId(),
      kind: kind,
      runtime: runtime,
      occurredAt: now(),
      sessionId: sessionId(),
      screen: crumbs.screen,
      exceptionType: type,
      exceptionMessage: message.map { String($0.prefix(CrashReport.maxMessage)) },
      frames: frames,
      context: context,
      breadcrumbs: crumbs.entries,
      debugImages: debugImages)
  }

  private func refreshSignalContext() {
    guard signalDirectory != nil else { return }
    let crumbs = breadcrumbs.snapshot()
    SignalCrashHandler.updateContext(SignalCrashContext.encode(.init(
      sessionId: sessionId(), screen: crumbs.screen, breadcrumbs: crumbs.entries)))
  }

  private func collectSignalCrash(in directory: URL) {
    let pending = SignalCrashFile.pendingURL(in: directory)
    guard let data = try? Data(contentsOf: pending) else { return }
    // Removed now, not left to the truncation at arming: if arming fails,
    // the same crash would be reported again on every launch.
    try? FileManager.default.removeItem(at: pending)
    guard let record = SignalCrashFile.parse(data),
          let sidecarData = try? Data(contentsOf: SignalCrashFile.sidecarURL(in: directory)),
          let sidecar = try? JSONDecoder().decode(SignalCrashFile.Sidecar.self, from: sidecarData)
    else { return }
    write(SignalCrashFile.report(record: record, sidecar: sidecar, inApp: inApp))
  }

  @MainActor
  private func armSignals(in directory: URL) {
    try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    let sidecar = SignalCrashFile.Sidecar(context: context, images: BinaryImages.loaded())
    guard let data = try? JSONEncoder().encode(sidecar),
          (try? data.write(to: SignalCrashFile.sidecarURL(in: directory), options: .atomic)) != nil
    else { return }
    SignalCrashHandler.setEnabled(consent != .denied)
    refreshSignalContext()
    SignalCrashHandler.install(pendingFile: SignalCrashFile.pendingURL(in: directory))
  }

  /// `NSURLErrorDomain(-1009)` for Cocoa errors, whose class says nothing;
  /// the Swift type otherwise (`MyApp.SyncError`).
  static func describe(_ error: any Error) -> (type: String, message: String?) {
    if type(of: error) is NSError.Type || error is any CustomNSError {
      let nsError = error as NSError
      return ("\(nsError.domain)(\(nsError.code))", nsError.localizedDescription)
    }
    // A private type reflects as `App.(unknown context at $1029c4f2c).SyncError`:
    // an address that moves with every build would split the issue.
    let name = String(reflecting: type(of: error))
      .replacing(/\(unknown context at \$[0-9a-fA-F]+\)\./, with: "")
    // Zero PII: an enum's case name only, never its associated values;
    // nothing for structs and classes, whose description is their fields.
    guard Mirror(reflecting: error).displayStyle == .enum else { return (name, nil) }
    let caseName = String(describing: error).prefix { $0 != "(" }
    return (name, caseName.isEmpty ? nil : String(caseName))
  }

  /// Bridge frames as the Flutter and React Native plugins send them.
  static func bridgedFrames(_ raw: [[String: Any]]) -> [CrashReport.Frame] {
    raw.prefix(CrashReport.maxFrames).map { entry in
      CrashReport.Frame(
        fn: entry["fn"] as? String ?? "",
        file: entry["file"] as? String,
        line: (entry["line"] as? NSNumber)?.intValue,
        col: (entry["col"] as? NSNumber)?.intValue,
        module: entry["module"] as? String,
        addr: nil,
        inApp: (entry["inApp"] as? NSNumber)?.boolValue ?? false)
    }
  }
}
