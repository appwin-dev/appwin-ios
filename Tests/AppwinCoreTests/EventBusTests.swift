import XCTest
import os
@_spi(Appwin) @testable import AppwinCore

final class EventBusTests: XCTestCase {
  func testADeniedPurposeSkipsItsSubscriberAndANilPurposeAlwaysHears() {
    let bus = EventBus(isGranted: { $0 == .analytics })
    let seen = OSAllocatedUnfairLock<[String]>(initialState: [])
    let ads = bus.subscribe(purpose: .advertising) { event in seen.withLock { $0.append("ads:\(event.name)") } }
    let skan = bus.subscribe(purpose: nil) { event in seen.withLock { $0.append("skan:\(event.name)") } }
    let crashes = bus.subscribe(purpose: .analytics) { event in seen.withLock { $0.append("crash:\(event.name)") } }
    bus.publish(EventBus.Event(name: "purchase", eventId: "e1", props: nil))
    XCTAssertEqual(seen.withLock { $0 }.sorted(), ["crash:purchase", "skan:purchase"])
    withExtendedLifetime((ads, skan, crashes)) {}
  }

  func testReleasingTheTokenUnsubscribes() {
    let bus = EventBus(isGranted: { _ in true })
    let seen = OSAllocatedUnfairLock<Int>(initialState: 0)
    var token: AnyObject? = bus.subscribe(purpose: nil) { _ in seen.withLock { $0 += 1 } }
    bus.publish(EventBus.Event(name: "a", eventId: "1", props: nil))
    token = nil
    bus.publish(EventBus.Event(name: "b", eventId: "2", props: nil))
    XCTAssertEqual(seen.withLock { $0 }, 1)
    withExtendedLifetime(token) {}
  }

  func testGrantAtPublishTimeDecidesDelivery() {
    let granted = OSAllocatedUnfairLock<Bool>(initialState: false)
    let bus = EventBus(isGranted: { _ in granted.withLock { $0 } })
    let seen = OSAllocatedUnfairLock<Int>(initialState: 0)
    let token = bus.subscribe(purpose: .advertising) { _ in seen.withLock { $0 += 1 } }
    bus.publish(EventBus.Event(name: "a", eventId: "1", props: nil))
    granted.withLock { $0 = true }
    bus.publish(EventBus.Event(name: "a", eventId: "2", props: nil))
    XCTAssertEqual(seen.withLock { $0 }, 1)
    withExtendedLifetime(token) {}
  }
}
