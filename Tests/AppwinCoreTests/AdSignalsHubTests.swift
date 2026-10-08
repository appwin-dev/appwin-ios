import XCTest

@testable import AppwinCore

final class AdSignalsHubTests: XCTestCase {
  private final class FakeAdapter: AdSignalsAdapter, @unchecked Sendable {
    let network: String
    private let lock = NSLock()
    private var _activations = 0
    private var _deactivations = 0
    private var _config: [String: String]?
    private var _events: [(String, String)] = []

    init(network: String) {
      self.network = network
    }

    func activate(config: [String: String]) {
      lock.lock()
      defer { lock.unlock() }
      _activations += 1
      _config = config
    }

    func deactivate() {
      lock.lock()
      defer { lock.unlock() }
      _deactivations += 1
    }

    func onEvent(name: String, eventId: String, props: [String: AnalyticsValue]?) {
      lock.lock()
      defer { lock.unlock() }
      _events.append((name, eventId))
    }

    var activations: Int {
      lock.lock()
      defer { lock.unlock() }
      return _activations
    }
    var deactivations: Int {
      lock.lock()
      defer { lock.unlock() }
      return _deactivations
    }
    var config: [String: String]? {
      lock.lock()
      defer { lock.unlock() }
      return _config
    }
    var events: [(String, String)] {
      lock.lock()
      defer { lock.unlock() }
      return _events
    }
  }

  private final class ConsentBox: @unchecked Sendable {
    private let lock = NSLock()
    private var value: AdvertisingConsent = .granted
    var consent: AdvertisingConsent {
      get {
        lock.lock()
        defer { lock.unlock() }
        return value
      }
      set {
        lock.lock()
        defer { lock.unlock() }
        value = newValue
      }
    }
  }

  private func makeClient(networksJson: String) -> ClientApi {
    ClientApi(
      baseUrl: "http://test",
      headersProvider: { [:] },
      dataFor: { request in
        let data = Data(networksJson.utf8)
        let response = HTTPURLResponse(
          url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!
        return (data, response)
      })
  }

  func testActivatesAWiredNetworkUnderGrantedConsent() async {
    let adapter = FakeAdapter(network: "tiktok")
    let box = ConsentBox()
    let client = makeClient(networksJson: #"{"networks":{"tiktok":{"appId":"741234"}}}"#)
    let hub = AdSignalsHub(client: { client }, consent: { box.consent }, adapters: [adapter])

    await hub.start()

    XCTAssertEqual(adapter.activations, 1)
    XCTAssertEqual(adapter.config?["appId"], "741234")

    hub.onEvent(name: "purchase", eventId: "evt-1", props: nil)
    // onEvent hops through a Task: give the actor a turn.
    await Task.yield()
    try? await Task.sleep(nanoseconds: 50_000_000)
    XCTAssertEqual(adapter.events.map(\.0), ["purchase"])
    XCTAssertEqual(adapter.events.map(\.1), ["evt-1"])
  }

  func testUnwiredNetworkNeverActivates() async {
    let adapter = FakeAdapter(network: "tiktok")
    let box = ConsentBox()
    let client = makeClient(networksJson: #"{"networks":{}}"#)
    let hub = AdSignalsHub(client: { client }, consent: { box.consent }, adapters: [adapter])

    await hub.start()

    XCTAssertEqual(adapter.activations, 0)
    hub.onEvent(name: "purchase", eventId: "evt-1", props: nil)
    try? await Task.sleep(nanoseconds: 50_000_000)
    XCTAssertTrue(adapter.events.isEmpty)
  }

  func testConsentWithdrawalDeactivates() async {
    let adapter = FakeAdapter(network: "tiktok")
    let box = ConsentBox()
    let client = makeClient(networksJson: #"{"networks":{"tiktok":{"appId":"1"}}}"#)
    let hub = AdSignalsHub(client: { client }, consent: { box.consent }, adapters: [adapter])

    await hub.start()
    XCTAssertEqual(adapter.activations, 1)

    box.consent = .denied
    await hub.onConsentChanged()
    XCTAssertEqual(adapter.deactivations, 1)

    hub.onEvent(name: "purchase", eventId: "evt-1", props: nil)
    try? await Task.sleep(nanoseconds: 50_000_000)
    XCTAssertTrue(adapter.events.isEmpty)
  }
}
