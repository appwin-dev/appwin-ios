import Foundation
import os

private let crashReporterHolder = OSAllocatedUnfairLock<CrashReporter?>(initialState: nil)

extension AppwinCore {
  // MARK: - Crashes (ADR-0056)

  /// The running reporter, nil until `startCrashReporting`. Read without
  /// waiting: the uncaught exception handler reads it from the dying thread.
  nonisolated static var crashReporter: CrashReporter? {
    crashReporterHolder.withLockIfAvailable { $0 } ?? nil
  }

  /// Wired by `AppwinAnalytics.initialize()` after the event pipeline, whose
  /// consent and session it reads. Idempotent.
  package static func startCrashReporting(inAppModules: [String]) {
    guard let projectAppId, let apiClient = client else { return }
    ensureEventPipeline()
    guard crashReporter == nil else { return }

    let prefs = UserDefaultsAnalyticsPrefs()
    let keyPrefix = "appwin.analytics.\(projectAppId)."
    let directory = FileManager.default
      .urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
      .appendingPathComponent("appwin/analytics/\(projectAppId)", isDirectory: true)
    let reporter = CrashReporter(
      store: CrashStore(directory: directory.appendingPathComponent("crashes", isDirectory: true)),
      sender: ApiCrashSender(client: { apiClient }),
      context: CrashContext.current(sdkVersion: version),
      inApp: InAppModules(inAppModules),
      signalDirectory: directory.appendingPathComponent("crash-signal", isDirectory: true),
      // Read from the prefs, not the pipeline's ConsentStore: that one is
      // confined to the pipeline actor, these reads happen on any thread.
      storedConsent: {
        prefs.string(forKey: keyPrefix + "consent").flatMap(AnalyticsConsent.init(rawValue:)) ?? .granted
      },
      sessionId: { prefs.string(forKey: keyPrefix + "session.id") },
      reauthorize: { (try? await AppwinCore.bootstrapSession()) != nil })
    crashReporterHolder.withLock { $0 = reporter }
    reporter.start()
  }

  package nonisolated static func recordError(_ error: any Error, returnAddresses: [NSNumber]) {
    guard let reporter = crashReporter else {
      return reportAnalyticsMisuse("recordError ignored, crash reporting is not started")
    }
    reporter.recordError(error, returnAddresses: returnAddresses.map(\.uint64Value))
  }

  package nonisolated static func recordBridgedError(
    runtime: String, fatal: Bool, type: String, message: String?, frames: [[String: Any]]
  ) {
    guard runtime == "flutter" || runtime == "react_native", let reporter = crashReporter else { return }
    reporter.recordBridged(
      runtime: runtime, fatal: fatal, type: type, message: message,
      frames: CrashReporter.bridgedFrames(frames))
  }

  /// Test seam: swaps the reporter the entry points route to.
  nonisolated static func setCrashReporterForTesting(_ reporter: CrashReporter?) {
    crashReporterHolder.withLock { $0 = reporter }
  }
}
