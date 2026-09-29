import Foundation
import AppwinCore

/// Appwin Analytics: behavioral events for the dashboards, funnels and
/// experiments of the Appwin studio.
///
/// The heavy lifting - persisted queue, batching, offline buffering, session
/// tracking, GDPR consent - lives in `AppwinCore` and starts with
/// `AppwinCore.configure(projectAppId:)`. This façade is the product's public
/// surface, like `AppwinSupport` or `AppwinNotifications` for theirs.
///
/// ```swift
/// AppwinCore.configure(projectAppId: "…")
/// AppwinAnalytics.setConsent(.granted)
/// AppwinAnalytics.screen("home")
/// AppwinAnalytics.track("purchase", props: ["plan": "pro", "seats": 3])
/// ```
public enum AppwinAnalytics {
  /// Starts the event pipeline, availability permitting. Call it once after
  /// `AppwinCore.configure`, as early as you want the capture to begin -
  /// sessions and installs are only recorded from this point on.
  ///
  /// Same contract as the other products: the server verdict (plan, product
  /// toggle) gates the start, the result is cached on disk so an offline
  /// launch falls back to the last known answer, and repeated calls are
  /// cheap.
  @MainActor
  public static func initialize() async -> AppwinInitResult {
    let result = await AppwinCore.availability(of: .analytics)
    isReady = result.isReady
    if !result.isReady {
      AppwinCore.reportUnavailable(.analytics, result)
    } else {
      AppwinCore.startAnalytics()
    }
    return result
  }

  /// Whether `initialize()` has returned `.ready`.
  @MainActor
  public private(set) static var isReady = false

  /// Queues a custom analytics event. Never blocks and never throws: the
  /// event is persisted locally and uploaded in batches (offline included).
  ///
  /// `name` must match `^[a-z][a-z0-9_]{0,63}$` and not shadow a reserved
  /// name (`session_start`, `session_end`, `screen_view`, `app_install`,
  /// `app_update`); invalid events are dropped with a debug log. Props are
  /// capped at 20 keys; string values are truncated to 256 characters.
  public static func track(_ name: String, props: [String: AnalyticsValue]? = nil) {
    AppwinCore.track(name, props: props)
  }

  /// Emits the reserved `screen_view` event for `name` (truncated to 128
  /// characters). Screen names feed funnel steps and breakdowns.
  public static func screen(_ name: String) {
    AppwinCore.screen(name)
  }

  /// Forces an immediate upload of the pending queue. Rarely needed: the
  /// pipeline already flushes on volume, on a timer, and when the app goes
  /// to the background.
  public static func flush() {
    AppwinCore.flush()
  }

  /// Sets the GDPR consent for analytics. The default is `.granted`
  /// (opt-out): most studios fall under the first-party audience-measurement
  /// exemption and need no consent screen. If yours has one, call
  /// `setConsent(.unknown)` at launch (before `configure` works too) -
  /// events are then captured and persisted but never uploaded - and then
  /// relay the user's answer:
  /// `.granted` uploads the backlog, `.denied` purges it and mutes capture.
  public static func setConsent(_ consent: AnalyticsConsent) {
    AppwinCore.setConsent(consent)
  }
}
