import Foundation
#if os(iOS)
import StoreKit
#endif
#if canImport(AdAttributionKit)
import AdAttributionKit
#endif

/// One rule of the server-defined conversion value schema (ADR-0038):
/// tracking `event` raises the SKAdNetwork/AdAttributionKit conversion
/// value to `value`. The value never goes down - it encodes the best
/// milestone this install reached.
struct ConversionRule: Codable, Sendable, Equatable {
  let event: String
  let value: Int
  let coarse: String
}

struct ConversionSchema: Codable, Sendable, Equatable {
  let version: Int
  let rules: [ConversionRule]
}

/// appwin is the single manager of the conversion value (ADR-0038): no
/// network SDK ever calls the update APIs. This actor caches the server
/// schema, registers the install at value 0, and raises the value when a
/// schema event is tracked.
///
/// No consent gate on purpose: the conversion value is an OS-level
/// aggregate on Apple's own privacy rail (crowd anonymity, no
/// identifiers, ATT-independent by design) - nothing leaves the device
/// to appwin or anyone else here.
actor ConversionValueManager {
  /// Mirror of the server default: the first launch - the one SKAN cares
  /// most about - can happen before any schema fetch succeeds.
  static let defaultSchema = ConversionSchema(
    version: 1,
    rules: [
      ConversionRule(event: "start_trial", value: 32, coarse: "medium"),
      ConversionRule(event: "purchase", value: 63, coarse: "high"),
    ])

  private let prefs: AnalyticsPrefs
  private let keyPrefix: String
  private let client: @Sendable () -> ClientApi?
  /// Seam for tests; production wires the StoreKit/AdAttributionKit call.
  private let applyUpdate: @Sendable (Int, String) async -> Void
  private var schema: ConversionSchema

  init(
    prefs: AnalyticsPrefs,
    keyPrefix: String,
    client: @escaping @Sendable () -> ClientApi?,
    applyUpdate: @escaping @Sendable (Int, String) async -> Void = systemUpdate
  ) {
    self.prefs = prefs
    self.keyPrefix = keyPrefix
    self.client = client
    self.applyUpdate = applyUpdate
    if let json = prefs.string(forKey: keyPrefix + "cv.schema"),
       let data = json.data(using: .utf8),
       let cached = try? JSONDecoder().decode(ConversionSchema.self, from: data) {
      schema = cached
    } else {
      schema = Self.defaultSchema
    }
  }

  /// Called once per analytics start: registers the install (value 0)
  /// on the very first run, then refreshes the schema from the server.
  func start() async {
    if prefs.string(forKey: keyPrefix + "cv.registered") == nil {
      prefs.set("1", forKey: keyPrefix + "cv.registered")
      await applyUpdate(0, "low")
    }
    await refresh()
  }

  func onEvent(_ name: String) async {
    guard let rule = schema.rules.first(where: { $0.event == name }) else { return }
    let current = Int(prefs.string(forKey: keyPrefix + "cv.current") ?? "") ?? 0
    guard rule.value > current else { return }
    prefs.set(String(rule.value), forKey: keyPrefix + "cv.current")
    await applyUpdate(rule.value, rule.coarse)
  }

  func currentSchema() -> ConversionSchema { schema }

  private func refresh() async {
    guard let api = client() else { return }
    do {
      let fresh: ConversionSchema = try await api.request(
        path: "/api/sdk/v1/attribution/conversion-schema", httpMethod: .get)
      guard fresh.version != schema.version else { return }
      schema = fresh
      if let data = try? JSONEncoder().encode(fresh), let json = String(data: data, encoding: .utf8) {
        prefs.set(json, forKey: keyPrefix + "cv.schema")
      }
    } catch {
      // Offline or server hiccup: the cache (or embedded default, which
      // mirrors the server default) keeps the first-launch window covered.
    }
  }

  /// AdAttributionKit when the OS has it, SKAdNetwork otherwise. Both are
  /// fire-and-forget: a failed update must never surface to the app.
  static let systemUpdate: @Sendable (Int, String) async -> Void = { fine, coarse in
    #if os(iOS)
    #if canImport(AdAttributionKit)
    if #available(iOS 17.4, *) {
      let aakCoarse: AdAttributionKit.CoarseConversionValue =
        coarse == "high" ? .high : coarse == "medium" ? .medium : .low
      try? await Postback.updateConversionValue(
        fine, coarseConversionValue: aakCoarse, lockPostback: false)
      return
    }
    #endif
    if #available(iOS 16.1, *) {
      let skCoarse: SKAdNetwork.CoarseConversionValue =
        coarse == "high" ? .high : coarse == "medium" ? .medium : .low
      SKAdNetwork.updatePostbackConversionValue(fine, coarseValue: skCoarse) { _ in }
    } else if #available(iOS 15.4, *) {
      SKAdNetwork.updatePostbackConversionValue(fine) { _ in }
    }
    #endif
  }
}
