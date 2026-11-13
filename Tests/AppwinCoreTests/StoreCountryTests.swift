import XCTest
@testable import AppwinCore

final class StoreCountryTests: XCTestCase {

  private func encoded(_ body: InitSessionBody) throws -> [String: Any] {
    let data = try JSONEncoder().encode(body)
    return try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
  }

  private func body(storeCountry: String?) -> InitSessionBody {
    InitSessionBody(
      deviceId: "device-1", externalId: nil, platform: "ios", model: "iPhone15,2",
      os: "17.4", appVersion: "1.0.0", language: "fr", sdkVersion: "1.2.0",
      storeCountry: storeCountry)
  }

  func testInitBodyCarriesTheStoreCountry() throws {
    let json = try encoded(body(storeCountry: "FRA"))
    XCTAssertEqual(json["storeCountry"] as? String, "FRA")
    XCTAssertEqual(json["deviceId"] as? String, "device-1")
    XCTAssertEqual(json["language"] as? String, "fr")
  }

  func testInitBodyOmitsAnUnknownStoreCountry() throws {
    let json = try encoded(body(storeCountry: nil))
    XCTAssertNil(json["storeCountry"])
  }

  func testNormalizedKeepsTwoOrThreeLetters() {
    XCTAssertEqual(StoreCountry.normalized("fra"), "FRA")
    XCTAssertEqual(StoreCountry.normalized(" US "), "US")
    XCTAssertNil(StoreCountry.normalized(nil))
    XCTAssertNil(StoreCountry.normalized(""))
    XCTAssertNil(StoreCountry.normalized("F"))
    XCTAssertNil(StoreCountry.normalized("FRAN"))
    XCTAssertNil(StoreCountry.normalized("F1A"))
  }

  func testFirstResultReturnsAFastAnswer() async {
    let value = await StoreCountry.firstResult(timeoutNanoseconds: 2_000_000_000) { "FRA" }
    XCTAssertEqual(value, "FRA")
  }

  func testFirstResultGivesUpOnAStalledStoreKit() async {
    let start = Date()
    let value: String? = await StoreCountry.firstResult(timeoutNanoseconds: 50_000_000) {
      try? await Task.sleep(nanoseconds: 5_000_000_000)
      return "FRA"
    }
    XCTAssertNil(value)
    XCTAssertLessThan(Date().timeIntervalSince(start), 2)
  }
}
