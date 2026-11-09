import XCTest
import UIKit
@_spi(Appwin) @testable import AppwinCore

final class AppLifecycleTests: XCTestCase {
  @MainActor
  func testSubscribersHearForegroundThenBackground() {
    AppLifecycle.reset(launchPending: true)
    var log: [String] = []
    let token = AppLifecycle.subscribe(
      onForeground: { log.append("fg") }, onBackground: { log.append("bg") })
    NotificationCenter.default.post(name: UIApplication.didBecomeActiveNotification, object: nil)
    NotificationCenter.default.post(name: UIApplication.didEnterBackgroundNotification, object: nil)
    XCTAssertEqual(log, ["fg", "bg"])
    withExtendedLifetime(token) {}
  }

  @MainActor
  func testReleasingTheTokenUnsubscribes() {
    AppLifecycle.reset(launchPending: true)
    var calls = 0
    var token: AnyObject? = AppLifecycle.subscribe(onForeground: { calls += 1 }, onBackground: {})
    token = nil
    NotificationCenter.default.post(name: UIApplication.didBecomeActiveNotification, object: nil)
    XCTAssertEqual(calls, 0)
    XCTAssertNil(token)
  }

  @MainActor
  func testOnlyLaunchAndARealReturnFromBackgroundAreForegrounds() {
    AppLifecycle.reset(launchPending: true)
    var log: [String] = []
    let token = AppLifecycle.subscribe(
      onForeground: { log.append("fg") }, onBackground: { log.append("bg") })
    let center = NotificationCenter.default
    center.post(name: UIApplication.didBecomeActiveNotification, object: nil)
    // Control Center, a system alert: inactive then active again, no background.
    center.post(name: UIApplication.didBecomeActiveNotification, object: nil)
    center.post(name: UIApplication.didEnterBackgroundNotification, object: nil)
    center.post(name: UIApplication.didBecomeActiveNotification, object: nil)
    XCTAssertEqual(log, ["fg", "bg", "fg"])
    withExtendedLifetime(token) {}
  }

  @MainActor
  func testNoLaunchForegroundWhenTheAppWasAlreadyActive() {
    AppLifecycle.reset(launchPending: false)
    var log: [String] = []
    let token = AppLifecycle.subscribe(
      onForeground: { log.append("fg") }, onBackground: { log.append("bg") })
    let center = NotificationCenter.default
    center.post(name: UIApplication.didBecomeActiveNotification, object: nil)
    XCTAssertEqual(log, [])
    center.post(name: UIApplication.didEnterBackgroundNotification, object: nil)
    center.post(name: UIApplication.didBecomeActiveNotification, object: nil)
    XCTAssertEqual(log, ["bg", "fg"])
    withExtendedLifetime(token) {}
  }
}

