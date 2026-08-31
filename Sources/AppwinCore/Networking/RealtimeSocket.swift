import Foundation

/// Raw socket event. Deliberately minimal: mapping to typed domain events
/// happens higher up, in `RealtimeHub` and the product SDKs.
public enum RealtimeSocketEvent: Sendable {
  /// Upgrade sent. Optimistic - see the note in `connect`.
  case opened
  /// Text frame: an `{v,t,id,data}` envelope, or an `{a:...}` control frame.
  case message(String)
  /// Closed by the server, the network, or a rejected auth. `code` is the
  /// WebSocket close code when available.
  case closed(code: Int?)
}

/// Low-level wrapper around `URLSessionWebSocketTask`, the only file in the SDK
/// that touches Apple's WebSocket API. One instance is one connection.
///
/// An `actor` because frames arrive on a background queue; isolating the state
/// is correct by construction under Swift 6.
///
/// Scope is deliberately small: connect, receive loop, ping, send text,
/// disconnect. `send` only serves the gateway control protocol (`sub`/`unsub`);
/// domain writes stay on HTTP. Reconnect, backoff and mobile lifecycle live
/// above, in `RealtimeClient`.
public actor RealtimeSocket {
  private let session: URLSession
  private var task: URLSessionWebSocketTask?
  private var receiveTask: Task<Void, Never>?
  private var readinessTask: Task<Void, Never>?
  private var onEvent: (@Sendable (RealtimeSocketEvent) -> Void)?
  /// `true` une fois l'upgrade prouvée (ping OK). Avant ça, `send` file
  /// dans `pendingSends` - sinon le hub perd ses `sub` (pas de room →
  /// pas d'events agent → thread SDK figé).
  private var isReady = false
  private var pendingSends: [String] = []

  public init(session: URLSession = .shared) {
    self.session = session
  }

  /// Opens the connection. The ephemeral realtime bearer (ADR-0028) rides on
  /// the upgrade request: `URLSessionWebSocketTask` accepts custom headers,
  /// unlike the browser `WebSocket`.
  public func connect(
    url: URL,
    token: String,
    onEvent: @escaping @Sendable (RealtimeSocketEvent) -> Void
  ) {
    disconnect()
    self.onEvent = onEvent
    self.isReady = false
    self.pendingSends = []

    var request = URLRequest(url: url)
    request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")

    let task = session.webSocketTask(with: request)
    self.task = task
    task.resume()

    // Optimistic: `resume()` does not confirm the upgrade. A rejected auth
    // surfaces as a throwing `receive()`, hence `.closed`. The real proof of an
    // open socket is the first `.message`, such as `sub:ok`.
    onEvent(.opened)

    receiveTask = Task { [weak self] in
      await self?.receiveLoop()
    }
    // No `onopen` on URLSessionWebSocketTask: the upgrade is proven with a
    // ping before `.opened` is emitted, otherwise `sub` leaves too early.
    readinessTask = Task { [weak self] in
      await self?.waitUntilReady()
    }
  }

  /// Closes the connection and stops the loop. Idempotent.
  public func disconnect() {
    readinessTask?.cancel()
    readinessTask = nil
    receiveTask?.cancel()
    receiveTask = nil
    task?.cancel(with: .goingAway, reason: nil)
    task = nil
    onEvent = nil
    isReady = false
    pendingSends = []
  }

  /// Sends a control frame (`sub`, `unsub`). Silent when the socket is closed:
  /// the hub replays subscriptions on every (re)connection.
  public func send(_ text: String) {
    if !isReady {
      pendingSends.append(text)
      return
    }
    flushSend(text)
  }

  /// RFC 6455 ping, driven by `RealtimeClient` to detect a half-open
  /// connection: `URLSessionWebSocketTask` does not surface server pings on
  /// iOS. Returns `false` when the ping fails.
  public func sendPing() async -> Bool {
    guard let task else { return false }
    return await withCheckedContinuation { (cont: CheckedContinuation<Bool, Never>) in
      task.sendPing { error in cont.resume(returning: error == nil) }
    }
  }

  /// Polls with pings until one succeeds, which proves the upgrade went
  /// through. Gives up after three seconds: past that, `receiveLoop` is the
  /// remaining safety net.
  private func waitUntilReady() async {
    for _ in 0..<60 {
      if Task.isCancelled { return }
      guard task != nil else { return }
      if await sendPing() {
        markReady()
        return
      }
      try? await Task.sleep(nanoseconds: 50_000_000)
    }
  }

  /// Opens the socket for real: emits `.opened` and drains what `send(_:)`
  /// queued while it was not ready yet. Idempotent, because both the ping and
  /// the first received frame can reach it.
  private func markReady() {
    guard !isReady else { return }
    isReady = true
    let queued = pendingSends
    pendingSends = []
    onEvent?(.opened)
    for text in queued {
      flushSend(text)
    }
  }

  private func flushSend(_ text: String) {
    task?.send(.string(text)) { _ in }
  }

  /// Receive loop. The `while` **is** the re-arming: `receive()` is one-shot
  /// and must be called again after every frame.
  private func receiveLoop() async {
    guard let task else { return }
    while !Task.isCancelled {
      do {
        let message = try await task.receive()
        // First frame means the socket is alive, in case the ping missed.
        if !isReady { markReady() }
        switch message {
        case .string(let text):
          onEvent?(.message(text))
        case .data(let data):
          // Binary channel is Yjs co-editing, not consumed by the SDK yet.
          _ = data
        @unknown default:
          break
        }
      } catch {
        if Task.isCancelled { break }
        let raw = task.closeCode.rawValue
        onEvent?(.closed(code: raw == 0 ? nil : raw))
        break
      }
    }
  }
}
