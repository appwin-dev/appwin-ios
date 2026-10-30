import Foundation

/// A product SDK, as the server names it in `/sdk/v1/availability`.
public enum AppwinProduct: String, Sendable, CaseIterable {
  case support
  case community
  case notifications
  case analytics
  case attribution
  /// Session replay (ADR-0057). Recorded by AppwinAnalytics, never opened by a
  /// product `initialize()` of its own.
  case replay
}

/// Why a product is closed to this app.
public enum AppwinUnavailableReason: String, Sendable {
  /// The organisation's plan does not include this product. The studio cannot
  /// fix this from the dashboard: it is a sales conversation.
  case plan
  /// The product is switched off for this project. The studio turns it back on
  /// from the dashboard, without shipping an app update.
  case disabled
}

/// Outcome of a product's `initialize()`.
///
/// A result rather than a thrown error, deliberately. "Not entitled" is an
/// expected outcome of a normal launch, not an exception: making callers write
/// `try` and a `catch` for the ordinary case pushes them towards `try?`, which
/// swallows the reason along with the failure.
public enum AppwinInitResult: Sendable, Equatable {
  /// Ready to present. This is the only value that unlocks the product's UI.
  case ready
  /// The server answered, and the answer is no.
  case unavailable(AppwinUnavailableReason)
  /// `AppwinCore.configure(projectAppId:)` was never called.
  case notConfigured
  /// No verdict could be obtained and nothing was cached from a previous
  /// launch. No network is one cause; an API too old to serve the endpoint is
  /// another. Retry later; do not treat it as a permanent no.
  case unknown

  public var isReady: Bool { self == .ready }
}

/// The organisation behind this app has paused its subscription: the product
/// stays in the app, and its screen says so instead of disappearing.
///
/// Support and Community report it as `.ready` from `initialize()`, so a host
/// app that gates its tab on `isReady` keeps the tab with no change. Read it
/// from `AppwinSupport.pause`, `AppwinCommunity.pause` or
/// `AppwinCore.pause(of:)`; it is `nil` when the product is not paused.
public struct AppwinPause: Sendable, Equatable, Codable {
  /// When the pause began, as the server wrote it (ISO 8601). Kept as text,
  /// never parsed: no screen shows it.
  public let since: String
  /// The headline the server chose, in the reader's language. Empty when the
  /// server sent none: the SDK screens then use their own text.
  public let title: String
  /// The explanation, with the same rules as `title`.
  public let message: String

  public init(since: String, title: String, message: String) {
    self.since = since
    self.title = title
    self.message = message
  }
}

/// What the server said about each product.
struct AvailabilityVerdict: Codable, Sendable {
  struct Status: Codable, Sendable {
    let enabled: Bool
    let reason: String?
    /// Open only because the request came from a debug build; release builds
    /// of the same app get `unavailable(plan)`.
    let debugOnly: Bool?
    /// Only `replay` carries one today. Decoded leniently: a malformed config
    /// must not void the verdict of every other product.
    let config: AppwinReplayConfig?
    /// Only a paused organisation's Support and Community carry one, beside
    /// `enabled: false, reason: "plan"`. Decoded leniently: a malformed one
    /// leaves the product plainly out of plan.
    let paused: PausedStatus?

    struct PausedStatus: Codable, Sendable {
      let since: String?
      let title: String?
      let message: String?
    }

    init(from decoder: any Decoder) throws {
      let container = try decoder.container(keyedBy: CodingKeys.self)
      enabled = try container.decode(Bool.self, forKey: .enabled)
      reason = try container.decodeIfPresent(String.self, forKey: .reason)
      debugOnly = try container.decodeIfPresent(Bool.self, forKey: .debugOnly)
      config = try? container.decodeIfPresent(AppwinReplayConfig.self, forKey: .config)
      paused = (try? container.decodeIfPresent(PausedStatus.self, forKey: .paused)) ?? nil
    }
  }
  let products: [String: Status]
}

/// Resolves and caches what this app is allowed to open.
///
/// One request for the three products, not one per product: an app that
/// integrates Support and Community would otherwise pay two round trips at
/// launch for an answer the server computes in one go.
///
/// ## Offline
///
/// The verdict is cached on disk and survives relaunches, so a plane journey
/// does not close a product the studio pays for. Only a first launch with no
/// network and no cache is genuinely undecided, and that answers `.unknown`
/// rather than a false no: locking a paying user out on a failed request is a
/// worse bug than briefly allowing one that lapsed.
actor AvailabilityStore {
  /// How long a cached verdict spares the network in RELEASE builds.
  ///
  /// Every end-user launch of every client app hits `/sdk/v1/availability`
  /// otherwise, for an answer that almost never changes. The trade-off is
  /// explicit: a dashboard toggle flip reaches a device at the first launch
  /// AFTER the TTL lapses, not the very next one. Debug builds always
  /// revalidate, so the integration loop (toggle, relaunch, ready) stays
  /// instant where developers live.
  static let revalidationTTL: TimeInterval = 3600

  private struct CachedVerdict: Codable {
    let verdict: AvailabilityVerdict
    let fetchedAt: Date
  }

  private var cached: CachedVerdict?
  private var inFlight: Task<AvailabilityVerdict?, Never>?

  private let defaultsKey: String

  init(appId: String) {
    self.defaultsKey = "appwin.core.availability.\(appId)"
  }

  /// Cached verdict, hydrated from disk on first access. A cache written by
  /// an older SDK (bare verdict, no timestamp) fails to decode and counts as
  /// absent - one extra fetch, then the new format takes over.
  private func hydrate() -> CachedVerdict? {
    if let cached { return cached }
    guard let data = UserDefaults.standard.data(forKey: defaultsKey),
          let decoded = try? JSONDecoder().decode(CachedVerdict.self, from: data)
    else { return nil }
    cached = decoded
    return decoded
  }

  private func persist(_ verdict: AvailabilityVerdict) {
    let entry = CachedVerdict(verdict: verdict, fetchedAt: Date())
    cached = entry
    if let data = try? JSONEncoder().encode(entry) {
      UserDefaults.standard.set(data, forKey: defaultsKey)
    }
  }

  /// Fetches the verdict, sharing one request between concurrent callers.
  ///
  /// Three products initialising at launch is the normal case, and without
  /// sharing that is three identical requests racing each other.
  func fetch(client: ClientApi) async -> AvailabilityVerdict? {
    #if !DEBUG
    if let fresh = hydrate(),
       Date().timeIntervalSince(fresh.fetchedAt) < Self.revalidationTTL {
      return fresh.verdict
    }
    #endif
    if let inFlight { return await inFlight.value }

    let task = Task<AvailabilityVerdict?, Never> { [defaultsKey] in
      _ = defaultsKey
      do {
        let verdict: AvailabilityVerdict = try await client.request(
          path: "/api/sdk/v1/availability",
          httpMethod: .get,
          extraHeaders: Self.languageHeader()
        )
        return verdict
      } catch {
        return nil
      }
    }
    inFlight = task
    let fresh = await task.value
    inFlight = nil

    if let fresh {
      persist(fresh)
      return fresh
    }
    // Network said nothing: the last known answer is better than no answer.
    return hydrate()?.verdict
  }

  /// The verdict already known, memory or disk, without touching the network.
  func cachedVerdict() -> AvailabilityVerdict? {
    hydrate()?.verdict
  }

  /// Device language, reduced to its ISO 639-1 code, so the server can word
  /// the pause screen. The region is dropped: `fr-CA` and `fr-FR` read the same.
  static func languageHeader(preferred: [String] = Locale.preferredLanguages) -> [String: String] {
    guard let code = preferred.first?.split(separator: "-").first else {
      return [:]
    }
    return ["X-Appwin-Language": String(code).lowercased()]
  }

  static func result(for product: AppwinProduct, in verdict: AvailabilityVerdict?) -> AppwinInitResult {
    guard let verdict else { return .unknown }
    // A product the server does not mention is not open. Unknown keys are
    // ignored rather than fatal, so a server that grows a product does not
    // break binaries already in the wild.
    guard let status = verdict.products[product.rawValue] else {
      return .unavailable(.disabled)
    }
    if status.enabled { return .ready }
    // Paused: the screen stays and says so. `.ready` is what keeps a host
    // app's existing tab; the pause itself comes from `pause(for:in:)`.
    if status.paused != nil { return .ready }
    return .unavailable(AppwinUnavailableReason(rawValue: status.reason ?? "") ?? .disabled)
  }

  /// The pause of `product`, `nil` when it is not paused. Missing texts become
  /// empty strings; each screen then uses its own.
  static func pause(for product: AppwinProduct, in verdict: AvailabilityVerdict?) -> AppwinPause? {
    guard let status = verdict?.products[product.rawValue], !status.enabled,
          let paused = status.paused else { return nil }
    return AppwinPause(
      since: paused.since ?? "",
      title: paused.title ?? "",
      message: paused.message ?? "")
  }

  static func isDebugOnly(_ product: AppwinProduct, in verdict: AvailabilityVerdict?) -> Bool {
    guard let status = verdict?.products[product.rawValue] else { return false }
    return status.enabled && status.debugOnly == true
  }
}
