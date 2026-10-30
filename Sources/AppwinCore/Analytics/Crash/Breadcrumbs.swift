import Foundation
import os

/// The last `capacity` screens and events, names only (zero PII, ADR-0056).
final class Breadcrumbs: Sendable {
  static let capacity = 20

  private struct State {
    var entries: [CrashReport.Breadcrumb] = []
    var screen: String?
  }

  private let state = OSAllocatedUnfairLock(initialState: State())
  private let now: @Sendable () -> Date

  init(now: @escaping @Sendable () -> Date = Date.init) {
    self.now = now
  }

  func screen(_ name: String) {
    let crumb = CrashReport.Breadcrumb(at: now(), type: .screen, name: name)
    state.withLock {
      $0.screen = name
      Self.append(crumb, to: &$0.entries)
    }
  }

  func event(_ name: String) {
    let crumb = CrashReport.Breadcrumb(at: now(), type: .event, name: name)
    state.withLock { Self.append(crumb, to: &$0.entries) }
  }

  /// Never waits: the uncaught exception handler calls this from the dying
  /// thread, which may have been interrupted while holding the lock. Empty
  /// then, rather than a deadlock.
  func snapshot() -> (entries: [CrashReport.Breadcrumb], screen: String?) {
    state.withLockIfAvailable { ($0.entries, $0.screen) } ?? ([], nil)
  }

  func clear() {
    state.withLock { $0 = State() }
  }

  private static func append(_ crumb: CrashReport.Breadcrumb, to entries: inout [CrashReport.Breadcrumb]) {
    entries.append(crumb)
    if entries.count > capacity { entries.removeFirst(entries.count - capacity) }
  }
}
