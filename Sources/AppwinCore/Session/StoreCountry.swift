// StoreCountry - the App Store account's country, sent on /sdk/v1/auth/init
// as `storeCountry`. The same country the stores (and RevenueCat) report for
// purchases, which the device locale or the SIM is not.

import Foundation
#if canImport(StoreKit)
import StoreKit
#endif

enum StoreCountry {
  /// Longest wait for the storefront on a session init. `Storefront.current`
  /// is usually instant but can stall (no App Store account, sandbox): past
  /// this, the init goes without the country.
  static let timeoutNanoseconds: UInt64 = 500_000_000

  /// Last country read in this process. The storefront only changes when the
  /// user switches App Store account, so a later init (an `identify`, a 401)
  /// does not wait again; the read is refreshed in the background.
  private static let cache = Locked<String?>(nil)

  /// The storefront's country (ISO 3166-1 alpha-3, e.g. "FRA"), or nil when
  /// StoreKit has none or does not answer within `timeoutNanoseconds`.
  /// Reading the storefront shows no prompt and needs no purchase.
  static func current() async -> String? {
    if let cached = cache.value {
      Task.detached { if let fresh = await read() { cache.value = fresh } }
      return cached
    }
    let country = await firstResult(timeoutNanoseconds: timeoutNanoseconds) { await read() }
    if let country { cache.value = country }
    return country
  }

  private static func read() async -> String? {
    #if canImport(StoreKit)
    if #available(iOS 15.0, macOS 12.0, tvOS 15.0, watchOS 8.0, *) {
      let code = await Storefront.current?.countryCode
      return normalized(code)
    }
    #endif
    return nil
  }

  /// Keeps a two or three letter code, upper-cased; anything else is nil.
  static func normalized(_ code: String?) -> String? {
    guard let trimmed = code?.trimmingCharacters(in: .whitespacesAndNewlines).uppercased(),
          (2...3).contains(trimmed.count),
          trimmed.allSatisfy({ $0.isASCII && $0.isLetter })
    else { return nil }
    return trimmed
  }

  /// Runs `operation` and returns its result, or nil once `timeoutNanoseconds`
  /// elapsed, whichever comes first. The operation is not awaited past the
  /// deadline (a StoreKit call may ignore cancellation).
  static func firstResult<T: Sendable>(
    timeoutNanoseconds: UInt64,
    operation: @escaping @Sendable () async -> T?
  ) async -> T? {
    let once = Locked(false)
    return await withCheckedContinuation { (continuation: CheckedContinuation<T?, Never>) in
      @Sendable func finish(_ value: T?) {
        let first = once.withLock { done -> Bool in
          if done { return false }
          done = true
          return true
        }
        if first { continuation.resume(returning: value) }
      }
      Task.detached { finish(await operation()) }
      Task.detached {
        try? await Task.sleep(nanoseconds: timeoutNanoseconds)
        finish(nil)
      }
    }
  }

  /// Test seam: forgets the cached country.
  static func resetCache() { cache.value = nil }
}

/// A value behind a lock, for the few statics above.
private final class Locked<Value>: @unchecked Sendable {
  private let lock = NSLock()
  private var stored: Value

  init(_ value: Value) { stored = value }

  var value: Value {
    get { lock.lock(); defer { lock.unlock() }; return stored }
    set { lock.lock(); defer { lock.unlock() }; stored = newValue }
  }

  func withLock<R>(_ body: (inout Value) -> R) -> R {
    lock.lock(); defer { lock.unlock() }
    return body(&stored)
  }
}
