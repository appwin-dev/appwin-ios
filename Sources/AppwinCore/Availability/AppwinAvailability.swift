import Foundation

/// A product SDK, as the server names it in `/sdk/v1/availability`.
public enum AppwinProduct: String, Sendable, CaseIterable {
  case support
  case community
  case notifications
  case analytics
  case attribution
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

/// What the server said about each product.
struct AvailabilityVerdict: Codable, Sendable {
  struct Status: Codable, Sendable {
    let enabled: Bool
    let reason: String?
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
          httpMethod: .get
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

  func status(for product: AppwinProduct, client: ClientApi) async -> AppwinInitResult {
    guard let verdict = await fetch(client: client) else { return .unknown }
    // A product the server does not mention is not open. Unknown keys are
    // ignored rather than fatal, so a server that grows a product does not
    // break binaries already in the wild.
    guard let status = verdict.products[product.rawValue] else {
      return .unavailable(.disabled)
    }
    if status.enabled { return .ready }
    return .unavailable(AppwinUnavailableReason(rawValue: status.reason ?? "") ?? .disabled)
  }
}
