// IdentityStore - SDK identity state, deliberately off the `@MainActor`.
//
// `AppwinCore.canonicalHeaders()` runs on every HTTP request, from a @Sendable
// closure on a background thread. These fields are pure data with no UI
// semantics, so keeping them on the MainActor forced a `MainActor.assumeIsolated`
// that trapped at runtime (`_dispatch_assert_queue_fail`) as soon as the closure
// really ran in the background.
//
// `OSAllocatedUnfairLock` gives thread-safe synchronous access with no actor hop
// and no `nonisolated(unsafe)`.

import Foundation
import os

/// Identity data injected into the canonical HTTP headers.
struct IdentityState: Sendable {
  var projectAppId: String?
  var deviceId: String?
  var externalId: String?
  var bearerToken: String?
  var sessionId: String?
  /// The externalId the current bearer was minted with. Differs from
  /// `externalId` between an `identify` and the bootstrap that follows it.
  var sessionExternalId: String?
}

/// Thread-safe source of truth for the SDK identity. Read synchronously by the
/// networking layer, mutated by `configure`, `identify` and `AuthSession`.
enum IdentityStore {
  static let lock = OSAllocatedUnfairLock(initialState: IdentityState())

  /// Reads under the lock.
  static func read<T: Sendable>(_ body: @Sendable (IdentityState) -> T) -> T {
    lock.withLock { body($0) }
  }

  /// Mutates under the lock.
  static func mutate(_ body: @Sendable (inout IdentityState) -> Void) {
    lock.withLock { body(&$0) }
  }
}
