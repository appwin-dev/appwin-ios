import XCTest
@_spi(Appwin) @testable import AppwinCore

#if canImport(UIKit)
import UIKit

/// The first foreground of a launch (`app_open`): an app woken in the
/// background by a silent push is not opened by anyone yet, and the real
/// opening that follows must still count.
@MainActor
final class LaunchForegroundTests: XCTestCase {
  private var appId = ""

  override func setUp() {
    super.setUp()
    appId = "launch-fg-\(UUID().uuidString.lowercased())"
    AppwinCore.resetEventPipelineForTesting()
    // Unanswered consent: events are queued on disk and never sent, so the
    // files below stay the whole record.
    AppwinCore.stageConsentForTesting(.unknown, for: nil)
    AppLifecycle.reset(launchPending: true)
  }

  override func tearDown() {
    AppwinCore.launchedInBackground = { UIApplication.shared.applicationState == .background }
    AppwinCore.resetEventPipelineForTesting()
    AppwinCore.resetConsentForTesting()
    super.tearDown()
  }

  private func queuedAppOpens() -> Int {
    let directory = FileManager.default
      .urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
      .appendingPathComponent("appwin/analytics/\(appId)", isDirectory: true)
    let files = (try? FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil)) ?? []
    return files.reduce(0) { total, file in
      let text = (try? String(contentsOf: file, encoding: .utf8)) ?? ""
      return total + text.components(separatedBy: "\"app_open\"").count - 1
    }
  }

  private func settle() async {
    try? await Task.sleep(nanoseconds: 400_000_000)
  }

  func testBackgroundLaunchEmitsNoAppOpenUntilTheAppIsOpened() async {
    AppwinCore.launchedInBackground = { true }
    AppwinCore.configure(projectAppId: appId)
    await settle()
    XCTAssertEqual(queuedAppOpens(), 0, "nobody opened the app yet")

    NotificationCenter.default.post(name: UIApplication.didBecomeActiveNotification, object: nil)
    await settle()
    XCTAssertEqual(queuedAppOpens(), 1, "the real opening counts")
  }

  func testInactiveColdLaunchEmitsExactlyOneAppOpen() async {
    AppwinCore.launchedInBackground = { false }
    AppwinCore.configure(projectAppId: appId)
    await settle()
    XCTAssertEqual(queuedAppOpens(), 1)

    NotificationCenter.default.post(name: UIApplication.didBecomeActiveNotification, object: nil)
    await settle()
    XCTAssertEqual(queuedAppOpens(), 1, "the launch activation adds no second one")
  }
}
#endif
