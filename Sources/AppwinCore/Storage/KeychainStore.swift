// Key-to-String storage in the keychain rather than UserDefaults, because it
// survives an app uninstall and is encrypted at rest. The device id lives here,
// so the anonymous identity is stable across reinstalls.

import Foundation
import Security

public enum KeychainStore {
  /// Namespaces our items away from other apps.
  private static let service = Bundle.main.bundleIdentifier ?? "com.appwin.core"

  /// Reads the value for `key`, or `nil`.
  public static func get(_ key: String) -> String? {
    var query = baseQuery(key)
    query[kSecReturnData as String] = true
    query[kSecMatchLimit as String] = kSecMatchLimitOne

    var result: AnyObject?
    let status = SecItemCopyMatching(query as CFDictionary, &result)
    guard status == errSecSuccess,
          let data = result as? Data,
          let value = String(data: data, encoding: .utf8) else { return nil }
    return value
  }

  /// Inserts or updates `key`. Returns `false` on keychain failure; the caller
  /// decides what to do about it.
  @discardableResult
  public static func set(_ value: String, forKey key: String) -> Bool {
    let data = Data(value.utf8)
    let query = baseQuery(key)

    if SecItemCopyMatching(query as CFDictionary, nil) == errSecSuccess {
      let attrs = [kSecValueData as String: data]
      return SecItemUpdate(query as CFDictionary, attrs as CFDictionary) == errSecSuccess
    } else {
      var insert = query
      insert[kSecValueData as String] = data
      // Readable from the first unlock after a reboot, and never synced to
      // another device.
      insert[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
      return SecItemAdd(insert as CFDictionary, nil) == errSecSuccess
    }
  }

  /// Deletes `key`. Returns `true` when removed or already absent.
  @discardableResult
  public static func delete(_ key: String) -> Bool {
    let status = SecItemDelete(baseQuery(key) as CFDictionary)
    return status == errSecSuccess || status == errSecItemNotFound
  }

  private static func baseQuery(_ key: String) -> [String: Any] {
    [
      kSecClass as String: kSecClassGenericPassword,
      kSecAttrService as String: service,
      kSecAttrAccount as String: key,
    ]
  }
}
