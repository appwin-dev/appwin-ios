import Foundation
import Network
#if canImport(UIKit)
import UIKit
#endif

/// High-level realtime client. Owns a low-level `RealtimeSocket` and adds the
/// four things that make it survive a real network:
///
///  - **reconnect + backoff**, driven by the socket's `.closed` events;
///  - **client-driven ping**: `URLSessionWebSocketTask` does not surface server
///    pings, so we ping ourselves to detect a half-open socket;
///  - **`NWPathMonitor`**: an interface change (wifi to cellular) reconnects
///    immediately instead of waiting out the backoff;
///  - **lifecycle**: background closes after a delay, foreground reconnects.
///
/// The `tokenProvider` is asynchronous because the realtime token is ephemeral
/// (60 s) and minted per (re)connection, so a revoked session loses realtime in
/// under a minute (ADR-0028).
public actor RealtimeClient {
  /// Lifecycle settings. Server-driven eventually; sane defaults meanwhile.
  public struct Config: Sendable {
    public var heartbeatInterval: TimeInterval
    /// How long to stay connected in the background before closing.
    public var backgroundTimeout: TimeInterval
    public var maxBackoff: TimeInterval

    public init(
      heartbeatInterval: TimeInterval = 25,
      backgroundTimeout: TimeInterval = 30,
      maxBackoff: TimeInterval = 30
    ) {
      self.heartbeatInterval = heartbeatInterval
      self.backgroundTimeout = backgroundTimeout
      self.maxBackoff = maxBackoff
    }
  }

  private let url: URL
  private let config: Config
  private let tokenProvider: @Sendable () async -> String?
  private let onEvent: @Sendable (RealtimeSocketEvent) -> Void

  private let socket = RealtimeSocket()
  private let pathMonitor = NWPathMonitor()

  /// `start()` was called, meaning we *want* a connection - not that we have one.
  private var isActive = false
  private var isBackgrounded = false
  private var backoffAttempt = 0
  private var lastPathStatus: NWPath.Status?

  private var connectTask: Task<Void, Never>?
  private var reconnectTask: Task<Void, Never>?
  private var heartbeatTask: Task<Void, Never>?
  private var backgroundTimer: Task<Void, Never>?
  private var lifecycleObservers: [NSObjectProtocol] = []
  #if canImport(UIKit)
  private var bgTaskId: UIBackgroundTaskIdentifier = .invalid
  #endif

  public init(
    url: URL,
    config: Config = .init(),
    tokenProvider: @escaping @Sendable () async -> String?,
    onEvent: @escaping @Sendable (RealtimeSocketEvent) -> Void
  ) {
    self.url = url
    self.config = config
    self.tokenProvider = tokenProvider
    self.onEvent = onEvent
  }

  // MARK: - Public lifecycle

  /// Arms network monitoring and system notifications, then connects. Idempotent.
  public func start() {
    guard !isActive else { return }
    isActive = true
    startPathMonitor()
    observeLifecycle()
    connect()
  }

  /// Stops everything and closes the socket. Idempotent.
  public func stop() {
    isActive = false
    connectTask?.cancel(); connectTask = nil
    reconnectTask?.cancel(); reconnectTask = nil
    heartbeatTask?.cancel(); heartbeatTask = nil
    backgroundTimer?.cancel(); backgroundTimer = nil
    pathMonitor.cancel()
    removeLifecycleObservers()
    Task { [socket] in await socket.disconnect() }
    endBackgroundTask()
  }

  /// Sends a text frame (gateway control protocol).
  public func send(_ text: String) async {
    await socket.send(text)
  }

  // MARK: - Connection

  private func connect() {
    guard isActive, !isBackgrounded else { return }
    connectTask?.cancel()
    connectTask = Task { [weak self] in
      await self?.connectNow()
    }
  }

  private func connectNow() async {
    guard isActive, !isBackgrounded else { return }

    // Ephemeral token, minted per connection. On failure (network, or
    // `/auth/init` not finished) retry through the backoff rather than opening
    // a socket that would be rejected with a 401.
    guard let token = await tokenProvider(), !Task.isCancelled else {
      scheduleReconnect()
      return
    }

    await socket.connect(url: url, token: token) { [weak self] event in
      guard let self else { return }
      Task { await self.handleSocketEvent(event) }
    }
    startHeartbeat()
  }

  private func handleSocketEvent(_ event: RealtimeSocketEvent) {
    switch event {
    case .opened:
      onEvent(event)
    case .message:
      // A received frame proves the connection is healthy: reset the backoff.
      backoffAttempt = 0
      onEvent(event)
    case .closed:
      onEvent(event)
      stopHeartbeat()
      if isActive, !isBackgrounded { scheduleReconnect() }
    }
  }

  private func scheduleReconnect() {
    reconnectTask?.cancel()
    let delay = backoffDelay()
    backoffAttempt += 1
    reconnectTask = Task { [weak self] in
      try? await Task.sleep(for: .seconds(delay))
      guard let self, !Task.isCancelled else { return }
      await self.connect()
    }
  }

  /// Capped exponential backoff with +/-20% jitter, so clients that dropped
  /// together do not reconnect together.
  private func backoffDelay() -> TimeInterval {
    let base = min(config.maxBackoff, pow(2.0, Double(min(backoffAttempt, 5))))
    return base * Double.random(in: 0.8...1.2)
  }

  // MARK: - Heartbeat

  private func startHeartbeat() {
    stopHeartbeat()
    let interval = config.heartbeatInterval
    heartbeatTask = Task { [weak self] in
      while !Task.isCancelled {
        try? await Task.sleep(for: .seconds(interval))
        guard let self, !Task.isCancelled else { break }
        let alive = await self.pingOnce()
        if !alive {
          await self.handleDeadConnection()
          break
        }
      }
    }
  }

  private func stopHeartbeat() {
    heartbeatTask?.cancel()
    heartbeatTask = nil
  }

  private func pingOnce() async -> Bool {
    await socket.sendPing()
  }

  /// A failed ping means a half-open socket that `receive()` never noticed.
  /// Reconnect fast, with the backoff reset since the connection was healthy.
  private func handleDeadConnection() {
    guard isActive, !isBackgrounded else { return }
    backoffAttempt = 0
    scheduleReconnect()
  }

  // MARK: - Network monitoring

  private func startPathMonitor() {
    pathMonitor.pathUpdateHandler = { [weak self] path in
      let status = path.status
      Task { await self?.handlePathUpdate(status) }
    }
    pathMonitor.start(queue: DispatchQueue(label: "com.appwin.realtime.path"))
  }

  private func handlePathUpdate(_ status: NWPath.Status) {
    defer { lastPathStatus = status }
    guard isActive, !isBackgrounded else { return }
    // Transition into "network available": reconnect now rather than waiting
    // out the backoff.
    if status == .satisfied, lastPathStatus != .satisfied {
      backoffAttempt = 0
      scheduleReconnect()
    }
  }

  // MARK: - Background and foreground

  private func observeLifecycle() {
    #if canImport(UIKit)
    let center = NotificationCenter.default
    let bg = center.addObserver(
      forName: UIApplication.didEnterBackgroundNotification,
      object: nil, queue: nil
    ) { [weak self] _ in
      Task { await self?.handleEnterBackground() }
    }
    let fg = center.addObserver(
      forName: UIApplication.willEnterForegroundNotification,
      object: nil, queue: nil
    ) { [weak self] _ in
      Task { await self?.handleEnterForeground() }
    }
    lifecycleObservers = [bg, fg]
    #endif
  }

  private func removeLifecycleObservers() {
    #if canImport(UIKit)
    let center = NotificationCenter.default
    for observer in lifecycleObservers { center.removeObserver(observer) }
    lifecycleObservers = []
    #endif
  }

  private func handleEnterBackground() {
    guard isActive, !isBackgrounded else { return }
    isBackgrounded = true
    beginBackgroundTask()
    // Do not cut immediately: a quick return to the foreground keeps the
    // connection. Otherwise close after `backgroundTimeout`.
    let timeout = config.backgroundTimeout
    backgroundTimer = Task { [weak self] in
      try? await Task.sleep(for: .seconds(timeout))
      guard let self, !Task.isCancelled else { return }
      await self.teardownForBackground()
    }
  }

  private func teardownForBackground() {
    stopHeartbeat()
    reconnectTask?.cancel(); reconnectTask = nil
    Task { [socket] in await socket.disconnect() }
    endBackgroundTask()
  }

  private func handleEnterForeground() {
    guard isActive else { return }
    isBackgrounded = false
    backgroundTimer?.cancel(); backgroundTimer = nil
    endBackgroundTask()
    // The REST resync is handled by the stores; here we only reconnect.
    backoffAttempt = 0
    connect()
  }

  // MARK: - UIKit background task

  private func beginBackgroundTask() {
    #if canImport(UIKit)
    Task { @MainActor [weak self] in
      let id = UIApplication.shared.beginBackgroundTask(withName: "com.appwin.realtime.bg") {
        // System expiration: close cleanly so the app is not killed.
        Task { await self?.teardownForBackground() }
      }
      await self?.storeBackgroundTaskId(id)
    }
    #endif
  }

  #if canImport(UIKit)
  private func storeBackgroundTaskId(_ id: UIBackgroundTaskIdentifier) {
    bgTaskId = id
  }
  #endif

  private func endBackgroundTask() {
    #if canImport(UIKit)
    let id = bgTaskId
    guard id != .invalid else { return }
    bgTaskId = .invalid
    Task { @MainActor in UIApplication.shared.endBackgroundTask(id) }
    #endif
  }
}
