import Foundation

/// Realtime layer errors.
///
/// Unlike `AppwinApiError`, these are **developer-facing**: they report a
/// misconfigured SDK, not an incident to show an end user. Realtime degrades
/// silently - the SDK stays functional over REST - so the UI never blocks on it.
public enum AppwinRealTimeError: Error {
  /// `AppwinCore.configure` was never called, so `projectAppId` or `deviceId`
  /// is missing and the gateway handshake cannot succeed.
  case notConfigured

  /// The supplied `baseUrl` is not a valid `URL`.
  case invalidUrl
}
