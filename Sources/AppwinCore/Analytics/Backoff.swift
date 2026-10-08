import Foundation

/// Exponential backoff with multiplicative jitter:
/// `min(cap, base * 2^attempt) * random(0.5...1.0)`.
///
/// The jitter is multiplicative (not additive) so concurrent devices that
/// failed together never re-converge on the same retry instant.
@_spi(Appwin) public struct Backoff: Sendable {
  let base: TimeInterval
  let cap: TimeInterval

  public init(base: TimeInterval, cap: TimeInterval) {
    self.base = base
    self.cap = cap
  }

  /// The curve of every SDK upload (events, crashes, replay segments), so a
  /// struggling API sees them all back off alike.
  public static let ingest = Backoff(base: 2, cap: 300)

  func delay(attempt: Int, using generator: inout some RandomNumberGenerator) -> TimeInterval {
    // Clamp the exponent: past the cap a bigger power changes nothing
    // and 2^attempt overflows for a long-lived retry loop.
    let exponent = min(attempt, 30)
    let raw = min(cap, base * pow(2, Double(exponent)))
    return raw * Double.random(in: 0.5...1.0, using: &generator)
  }

  public func delay(attempt: Int) -> TimeInterval {
    var generator = SystemRandomNumberGenerator()
    return delay(attempt: attempt, using: &generator)
  }
}
