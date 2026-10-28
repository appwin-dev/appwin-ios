import Foundation

/// Uncaught Objective-C exceptions (`NSInvalidArgumentException` and the
/// like): recorded on the dying thread, then handed to the handler installed
/// before (Crashlytics, Sentry keep working). The runtime calls `abort()`
/// right after, which the signal handler then lets through.
enum ExceptionCrashHandler {
  private static let lock = NSLock()
  nonisolated(unsafe) private static var installed = false
  nonisolated(unsafe) private static var previous: (@convention(c) (NSException) -> Void)?
  nonisolated(unsafe) private static var record: (@Sendable (NSException) -> Void)?
  nonisolated(unsafe) private static var handling = false

  /// Once per process; later calls are no-ops, never a second link in the
  /// chain. `record` therefore resolves its target itself, at crash time.
  static func install(record: @escaping @Sendable (NSException) -> Void) {
    lock.lock()
    defer { lock.unlock() }
    guard !installed else { return }
    installed = true
    self.record = record
    previous = NSGetUncaughtExceptionHandler()
    NSSetUncaughtExceptionHandler(appwinExceptionHandler)
  }

  fileprivate static func handle(_ exception: NSException) {
    lock.lock()
    // A second exception while recording the first goes straight to the
    // chain: one report per process death.
    let first = !handling
    handling = true
    let record = self.record
    let previous = self.previous
    lock.unlock()
    if first { record?(exception) }
    previous?(exception)
  }

  /// Test seam: puts back the handler found at install and forgets it.
  static func uninstallForTesting() {
    lock.lock()
    defer { lock.unlock() }
    guard installed else { return }
    NSSetUncaughtExceptionHandler(previous)
    installed = false
    handling = false
    previous = nil
    record = nil
  }
}

private func appwinExceptionHandler(_ exception: NSException) {
  ExceptionCrashHandler.handle(exception)
}
