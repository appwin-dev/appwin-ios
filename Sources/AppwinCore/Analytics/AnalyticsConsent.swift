import Foundation

/// GDPR consent state for the analytics pipeline.
///
/// `granted` is the default (opt-out, the PostHog model). `unknown` queues
/// events on disk but never sends them, so an app with a consent screen can
/// initialize the SDK before showing it without losing the first session.
/// `denied` purges the queue and disables capture.
public enum AnalyticsConsent: String, Sendable {
  case granted
  case denied
  case unknown
}
