import Foundation

/// What a user answered about a consent purpose.
///
/// `granted` is the default (opt-out, the PostHog model). `unknown` keeps
/// events on the device but never sends them, so an app with a consent screen
/// can initialize the SDK before showing it without losing the first session.
/// `denied` purges the queue and disables capture.
public enum ConsentState: String, Sendable {
  case granted
  case denied
  case unknown
}

@available(*, deprecated, renamed: "ConsentState")
public typealias AnalyticsConsent = ConsentState
