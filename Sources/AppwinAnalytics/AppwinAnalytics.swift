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
  ///
  /// Crash reporting starts with it: uncaught Objective-C exceptions and
  /// fatal signals (Swift traps such as `fatalError` or a force unwrap,
  /// `EXC_BAD_ACCESS`, `abort()`) are written to disk and uploaded on the
  /// next launch, with the app version, OS, device model, current screen and
  /// the last 20 screens and events (names only). Handlers installed before
  /// (Crashlytics, Sentry) keep receiving every crash. Same consent as the
  /// events. Crashes are not caught while a debugger is attached.
  ///
  /// - Parameters:
  ///   - crashReporting: `false` leaves crashes out entirely: no handler
  ///     installed, nothing captured, and `recordError` becomes a no-op.
  ///   - inAppModules: names of your own dynamic frameworks, when your code
  ///     does not all live in the app executable. Only frames from your code
  ///     group crashes into issues; the executable always counts.
  @MainActor
  public static func initialize(
    crashReporting: Bool = true,
    inAppModules: [String] = []
  ) async -> AppwinInitResult {
    let result = await AppwinCore.availability(of: .analytics)
    isReady = result.isReady
    if !result.isReady {
      AppwinCore.reportUnavailable(.analytics, result)
    } else {
      AppwinCore.startAnalytics()
      if crashReporting { AppwinCore.startCrashReporting(inAppModules: inAppModules) }
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

  /// Reports an error your code caught, as a non-fatal: its type, message
  /// and the call stack at this call, plus the current screen and the last
  /// 20 screens and events. Persisted right away, uploaded in the
  /// background. Never throws.
  ///
  /// ```swift
  /// do { try await sync() } catch { AppwinAnalytics.recordError(error) }
  /// ```
  ///
  /// The type is `domain(code)` for an `NSError` (`NSURLErrorDomain(-1009)`)
  /// and the Swift type otherwise (`MyApp.SyncError`). Dropped when
  /// analytics is not initialized or was initialized with
  /// `crashReporting: false`; nothing is recorded under `.denied` consent.
  @inline(never)
  public static func recordError(_ error: any Error) {
    // The first address is this function's own frame.
    AppwinCore.recordError(error, returnAddresses: Array(Thread.callStackReturnAddresses.dropFirst()))
  }

  /// For Appwin's Flutter and React Native plugins; not for app code.
  ///
  /// Records an error of the Dart or JavaScript runtime. `runtime` is
  /// `"flutter"` or `"react_native"` (anything else is ignored); each frame
  /// carries `fn` (String), and optionally `file` (String), `line` and `col`
  /// (Int), `module` (String), plus `inApp` (Bool). The report is on disk
  /// when this returns, so a fatal error survives the process being killed
  /// right after. Safe from any thread; dropped when crash reporting is not
  /// started.
  public static func recordBridgedError(
    runtime: String, fatal: Bool, type: String, message: String?, frames: [[String: Any]]
  ) {
    AppwinCore.recordBridgedError(
      runtime: runtime, fatal: fatal, type: type, message: message, frames: frames)
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
