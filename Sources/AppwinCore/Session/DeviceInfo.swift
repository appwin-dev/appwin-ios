import Foundation
import UIKit

/// Host device metadata, captured by `AppwinCore.configure` and sent to the
/// backend for telemetry and debugging.
public struct DeviceInfo: Sendable {
  public let platform: String
  public let model: String
  public let osVersion: String
  public let appVersion: String?

  public init(platform: String, model: String, osVersion: String, appVersion: String?) {
    self.platform = platform
    self.model = model
    self.osVersion = osVersion
    self.appVersion = appVersion
  }

  @MainActor
  public static func current() -> DeviceInfo {
    DeviceInfo(
      platform: "ios",
      model: UIDevice.current.model,
      osVersion: UIDevice.current.systemVersion,
      appVersion: Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String
    )
  }
}
