import Foundation

/// What an event may be used for. Each event leaves the device stamped with
/// the purposes granted at that moment.
public enum ConsentPurpose: String, CaseIterable, Sendable {
  case analytics
  case marketing
  case advertising
}
