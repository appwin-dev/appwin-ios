import Foundation

/// The conversation whose thread is on screen, `nil` when none is.
///
/// What the in-app banner tests before announcing a reply. The view hierarchy is
/// not the signal: embedded in a host app's tab bar the messenger stays mounted
/// on every tab, so suppressing while it exists would silence the banner for the
/// whole app. Suppressing while its *thread* is open is the thing actually meant
/// - the message is already visible.
///
/// A global rather than a lookup on `MessageStore`: the store is created per
/// messenger root and the watcher runs without one.
///
/// Mirrors `OpenThread` on Android.
@MainActor
enum OpenThread {
  static var conversationId: String?
}
