import XCTest

@testable import AppwinCore

final class AdIdentityReporterTests: XCTestCase {
  private final class RequestRecorder: @unchecked Sendable {
    private let lock = NSLock()
    private var recorded: [URLRequest] = []
    private var statuses: [Int]

    init(statuses: [Int]) {
      self.statuses = statuses
    }

    func handle(_ request: URLRequest) -> (Data, URLResponse) {
      lock.lock()
      defer { lock.unlock() }
      recorded.append(request)
      let status = statuses.isEmpty ? 204 : statuses.removeFirst()
      let response = HTTPURLResponse(
        url: request.url!, statusCode: status, httpVersion: nil, headerFields: nil)!
      return (Data(), response)
    }

    var all: [URLRequest] {
      lock.lock()
      defer { lock.unlock() }
      return recorded
    }
  }

  private func makeReporter(
    statuses: [Int] = [204],
    idfa: AdIdentityReporter.IdfaInfo?,
    prefs: InMemoryAnalyticsPrefs = InMemoryAnalyticsPrefs()
  ) -> (AdIdentityReporter, RequestRecorder, InMemoryAnalyticsPrefs) {
    let recorder = RequestRecorder(statuses: statuses)
    let client = ClientApi(
      baseUrl: "http://test",
      headersProvider: { [:] },
      dataFor: { request in recorder.handle(request) })
    let reporter = AdIdentityReporter(
      prefs: prefs,
      keyPrefix: "t.",
      client: { client },
      reauthorize: { false },
      idfaProvider: { idfa })
    return (reporter, recorder, prefs)
  }

  func testGrantedConsentUploadsTheIdfaOnce() async {
    let (reporter, recorder, prefs) = makeReporter(
      idfa: .init(id: "1DFA0000-90AB-CDEF-1234-567890ABCDEF", attStatus: "authorized"))

    await reporter.setConsent(.granted)

    XCTAssertEqual(recorder.all.count, 1)
    let request = recorder.all[0]
    XCTAssertEqual(request.httpMethod, "PUT")
    XCTAssertEqual(request.url?.path, "/api/sdk/v1/attribution/ad-identity")
    let body = try! JSONSerialization.jsonObject(with: request.httpBody!) as! [String: String]
    XCTAssertEqual(body["platform"], "ios")
    XCTAssertEqual(body["adId"], "1dfa0000-90ab-cdef-1234-567890abcdef")
    XCTAssertEqual(body["attStatus"], "authorized")
    XCTAssertEqual(prefs.string(forKey: "t.adid.sent"), "1dfa0000-90ab-cdef-1234-567890abcdef")

    // Same value again: no second call.
    await reporter.start()
    XCTAssertEqual(recorder.all.count, 1)
  }

  func testAttNotAuthorizedOverwritesWithANullIdentifier() async {
    let prefs = InMemoryAnalyticsPrefs()
    prefs.set("granted", forKey: "t.advertising.consent")
    prefs.set("1dfa0000-90ab-cdef-1234-567890abcdef", forKey: "t.adid.sent")
    let (reporter, recorder, _) = makeReporter(
      idfa: .init(id: nil, attStatus: "denied"), prefs: prefs)

    await reporter.start()

    XCTAssertEqual(recorder.all.map(\.httpMethod), ["PUT"])
    let body =
      try! JSONSerialization.jsonObject(with: recorder.all[0].httpBody!) as! [String: Any?]
    XCTAssertNil(body["adId"] as? String)
    XCTAssertEqual(body["attStatus"] as? String, "denied")
    XCTAssertEqual(prefs.string(forKey: "t.adid.sent"), "-")
  }

  func testDeniedConsentDeletesTheRemoteRow() async {
    let prefs = InMemoryAnalyticsPrefs()
    prefs.set("1dfa0000-90ab-cdef-1234-567890abcdef", forKey: "t.adid.sent")
    let (reporter, recorder, _) = makeReporter(
      idfa: .init(id: "1DFA0000-90AB-CDEF-1234-567890ABCDEF", attStatus: "authorized"),
      prefs: prefs)

    await reporter.setConsent(.denied)

    XCTAssertEqual(recorder.all.map(\.httpMethod), ["DELETE"])
    XCTAssertNil(prefs.string(forKey: "t.adid.sent"))
    XCTAssertEqual(prefs.string(forKey: "t.advertising.consent"), "denied")
  }

  func testZeroedIdfaReportsConsentWithANullIdentifier() async {
    let (reporter, recorder, prefs) = makeReporter(
      idfa: .init(id: "00000000-0000-0000-0000-000000000000", attStatus: "authorized"))

    await reporter.setConsent(.granted)

    XCTAssertEqual(recorder.all.map(\.httpMethod), ["PUT"])
    let body =
      try! JSONSerialization.jsonObject(with: recorder.all[0].httpBody!) as! [String: Any?]
    XCTAssertNil(body["adId"] as? String)
    XCTAssertEqual(prefs.string(forKey: "t.adid.sent"), "-")
  }

  func testFailedUploadRetriesAtNextStart() async {
    let (reporter, recorder, prefs) = makeReporter(
      statuses: [500, 204],
      idfa: .init(id: "1DFA0000-90AB-CDEF-1234-567890ABCDEF", attStatus: "authorized"))

    await reporter.setConsent(.granted)
    XCTAssertNil(prefs.string(forKey: "t.adid.sent"))

    await reporter.start()
    XCTAssertEqual(recorder.all.count, 2)
    XCTAssertEqual(prefs.string(forKey: "t.adid.sent"), "1dfa0000-90ab-cdef-1234-567890abcdef")
  }
}
