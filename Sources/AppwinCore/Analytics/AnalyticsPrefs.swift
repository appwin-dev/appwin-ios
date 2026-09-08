import Foundation

/// Tiny string-only key-value seam over UserDefaults, so session and consent
/// logic can be tested with an in-memory map. Numbers are stored as strings:
/// one type keeps the seam trivial on both platforms.
protocol AnalyticsPrefs: AnyObject, Sendable {
  func string(forKey key: String) -> String?
  func set(_ value: String?, forKey key: String)
}

/// UserDefaults is documented thread-safe, hence the unchecked conformance.
final class UserDefaultsAnalyticsPrefs: AnalyticsPrefs, @unchecked Sendable {
  private let defaults: UserDefaults

  init(defaults: UserDefaults = .standard) {
    self.defaults = defaults
  }

  func string(forKey key: String) -> String? {
    defaults.string(forKey: key)
  }

  func set(_ value: String?, forKey key: String) {
    if let value {
      defaults.set(value, forKey: key)
    } else {
      defaults.removeObject(forKey: key)
    }
  }
}

final class InMemoryAnalyticsPrefs: AnalyticsPrefs, @unchecked Sendable {
  private let lock = NSLock()
  private var values: [String: String] = [:]

  func string(forKey key: String) -> String? {
    lock.lock()
    defer { lock.unlock() }
    return values[key]
  }

  func set(_ value: String?, forKey key: String) {
    lock.lock()
    defer { lock.unlock() }
    values[key] = value
  }
}
