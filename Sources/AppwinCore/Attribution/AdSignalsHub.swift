import Foundation

/// Orchestrates the ad-signals adapters (ADR-0038): loads whatever
/// adapter modules the app ships, fetches the dashboard wiring once per
/// start, and reconciles - an adapter runs exactly when its network is
/// wired AND the advertising consent is granted. Everything is best
/// effort: a broken adapter must never take the host app down.
actor AdSignalsHub {
  private struct ConfigResponse: Decodable {
    let networks: [String: [String: String]]
  }

  private let client: @Sendable () -> ClientApi?
  private let consent: @Sendable () -> AdvertisingConsent
  private let adapters: [AdSignalsAdapter]
  private var configs: [String: [String: String]] = [:]
  private var active: Set<String> = []

  init(
    client: @escaping @Sendable () -> ClientApi?,
    consent: @escaping @Sendable () -> AdvertisingConsent,
    adapters: [AdSignalsAdapter] = loadAdSignalsAdapters()
  ) {
    self.client = client
    self.consent = consent
    self.adapters = adapters
  }

  func start() async {
    guard !adapters.isEmpty else { return }
    await fetchConfig()
    reconcile()
  }

  func onConsentChanged() {
    guard !adapters.isEmpty else { return }
    reconcile()
  }

  nonisolated func onEvent(name: String, eventId: String, props: [String: AnalyticsValue]?) {
    Task { await self.dispatch(name: name, eventId: eventId, props: props) }
  }

  private func dispatch(name: String, eventId: String, props: [String: AnalyticsValue]?) {
    guard !active.isEmpty else { return }
    for adapter in adapters where active.contains(adapter.network) {
      adapter.onEvent(name: name, eventId: eventId, props: props)
    }
  }

  private func fetchConfig() async {
    guard let api = client() else { return }
    do {
      let response: ConfigResponse = try await api.request(
        path: "/api/sdk/v1/attribution/activation-config", httpMethod: .get)
      configs = response.networks
    } catch {
      // Unreachable config = nothing activates; next start retries.
      configs = [:]
    }
  }

  /// Idempotent per adapter: activation state changes fire the hooks once.
  private func reconcile() {
    let granted = consent() == .granted
    for adapter in adapters {
      let config = configs[adapter.network]
      let shouldRun = granted && config != nil
      let isRunning = active.contains(adapter.network)
      if shouldRun && !isRunning {
        adapter.activate(config: config ?? [:])
        active.insert(adapter.network)
      } else if !shouldRun && isRunning {
        adapter.deactivate()
        active.remove(adapter.network)
      }
    }
  }
}
