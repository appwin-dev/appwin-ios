import Foundation

/// Multiplexed realtime hub (ADR-0028 §9): **one WebSocket connection per
/// app**, shared by every product SDK. Products subscribe by event name and the
/// hub routes.
///
/// Gateway protocol:
///  1. `POST /sdk/v1/realtime/token` with the session bearer returns a 60 s
///     token whose claims carry the exact list of allowed topics.
///  2. Connect to `wss://ws.<domain>/ws` with that token as a header.
///  3. Send `{"a":"sub","topic":…}` per topic, expect `sub:ok`.
///  4. Events arrive in a versioned `{v,t,id,data}` envelope and dispatch on
///     `t`. Delivery is at-most-once, so stores resync over REST on reconnect
///     through the `onConnected` callback.
///
/// Push-only: no mutation leaves through the socket. The typing indicator, the
/// only write-over-WS in the legacy Socket.IO setup, goes over HTTP.
public final class RealtimeHub: @unchecked Sendable {
  private struct TokenResponse: Decodable {
    let token: String
    let expiresIn: Int
  }

  private struct TokenClaims: Decodable {
    let topics: [String]
  }

  private let lock = NSLock()
  private var client: RealtimeClient?
  private var handlers: [String: [(id: UUID, callback: @Sendable (Any?) -> Void)]] = [:]
  private var connectedCallbacks: [(id: UUID, callback: @Sendable () -> Void)] = []
  private var topics: [String] = []
  private var started = false

  private let gatewayUrl: URL
  private let mintToken: @Sendable () async -> String?

  /// - Parameters:
  ///   - gatewayUrl: full WS endpoint URL (`wss://ws.appwin.io/ws`).
  ///   - mintToken: mints the ephemeral token, called on every reconnection.
  ///     The hub decodes its claims to know which topics to subscribe to.
  public init(gatewayUrl: URL, mintToken: @escaping @Sendable () async -> String?) {
    self.gatewayUrl = gatewayUrl
    self.mintToken = mintToken
  }

  /// Builds a hub wired to the SDK API, minting through the canonical client.
  public static func make(gatewayUrl: URL, api: ClientApi) -> RealtimeHub {
    RealtimeHub(gatewayUrl: gatewayUrl) {
      let response: TokenResponse? = try? await api.request(
        path: "/api/sdk/v1/realtime/token",
        httpMethod: .post
      )
      return response?.token
    }
  }

  // MARK: - Product surface

  /// Subscribes to a domain event (`support.message.created`, …). The handler
  /// receives the envelope's `data`. Returns an id for `off(_:)`. The first
  /// subscriber starts the connection.
  @discardableResult
  public func on(event: String, callback: @escaping @Sendable (Any?) -> Void) -> UUID {
    let id = UUID()
    lock.lock()
    handlers[event, default: []].append((id, callback))
    lock.unlock()
    ensureStarted()
    return id
  }

  public func off(_ id: UUID) {
    lock.lock()
    for (event, list) in handlers {
      handlers[event] = list.filter { $0.id != id }
    }
    connectedCallbacks.removeAll { $0.id == id }
    lock.unlock()
  }

  /// (Re)connection callback, which drives the stores' REST resync
  /// (at-most-once semantics, ADR-0028 §7).
  @discardableResult
  public func onConnected(_ callback: @escaping @Sendable () -> Void) -> UUID {
    let id = UUID()
    lock.lock()
    connectedCallbacks.append((id, callback))
    lock.unlock()
    ensureStarted()
    return id
  }

  /// Cuts the connection. Handlers stay registered: a `start()` or a new
  /// `on(...)` brings it back.
  public func stop() {
    lock.lock()
    let client = self.client
    self.client = nil
    started = false
    lock.unlock()
    Task { await client?.stop() }
  }

  public func start() {
    ensureStarted()
  }

  // MARK: - Connection

  private func ensureStarted() {
    lock.lock()
    defer { lock.unlock() }
    guard !started else { return }
    started = true

    let mint = mintToken
    let client = RealtimeClient(
      url: gatewayUrl,
      tokenProvider: { [weak self] in
        guard let token = await mint() else { return nil }
        self?.rememberTopics(from: token)
        return token
      },
      onEvent: { [weak self] event in
        self?.handleSocketEvent(event)
      }
    )
    self.client = client
    Task { await client.start() }
  }

  /// Topics read from the token claims. The server stays the only source of
  /// authorisation: the gateway checks them again at subscribe time.
  private func rememberTopics(from token: String) {
    let parts = token.split(separator: ".")
    guard parts.count == 3 else { return }
    var base64 = String(parts[1])
      .replacingOccurrences(of: "-", with: "+")
      .replacingOccurrences(of: "_", with: "/")
    while base64.count % 4 != 0 { base64 += "=" }
    guard
      let data = Data(base64Encoded: base64),
      let claims = try? JSONDecoder().decode(TokenClaims.self, from: data)
    else { return }
    lock.lock()
    topics = claims.topics
    lock.unlock()
  }

  private func handleSocketEvent(_ event: RealtimeSocketEvent) {
    switch event {
    case .opened:
      subscribeAll()
    case .message(let text):
      handleMessage(text)
    case .closed:
      // RealtimeClient handles the reconnect; we only re-arm `onConnected`
      // for the next connection.
      lock.lock()
      connectedNotified = false
      lock.unlock()
    }
  }

  private func subscribeAll() {
    lock.lock()
    let client = self.client
    let topics = self.topics
    lock.unlock()
    guard let client else { return }
    Task {
      for topic in topics {
        await client.send(#"{"a":"sub","topic":"\#(topic)"}"#)
      }
    }
  }

  private func handleMessage(_ text: String) {
    guard
      let data = text.data(using: .utf8),
      let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
    else { return }

    // Gateway control frames (`sub:ok`, `sub:err`, `pong`): nothing to route.
    if json["a"] != nil {
      // The first `sub:ok` is the proof the connection is really up.
      if json["a"] as? String == "sub:ok" {
        notifyConnectedOnce()
      }
      return
    }

    // Domain envelope `{v,t,id,data}`.
    guard let eventName = json["t"] as? String else { return }
    lock.lock()
    let callbacks = handlers[eventName]?.map(\.callback) ?? []
    lock.unlock()
    guard !callbacks.isEmpty else { return }
    let payload = json["data"]
    for callback in callbacks { callback(payload) }
  }

  /// `onConnected` must fire once per connection, not once per `sub:ok`, hence
  /// the flag reset on close.
  private var connectedNotified = false
  private func notifyConnectedOnce() {
    lock.lock()
    let shouldNotify = !connectedNotified
    connectedNotified = true
    let callbacks = connectedCallbacks.map(\.callback)
    lock.unlock()
    guard shouldNotify else { return }
    for callback in callbacks { callback() }
  }
}
