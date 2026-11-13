import Foundation

/// The post whose detail is on screen, `nil` when none is.
///
/// What the in-app banner tests before announcing activity. Suppressing while
/// Community is mounted would silence every banner for a tabbed host; suppressing
/// while *that post* is open is the thing meant - the activity is already visible.
///
/// Mirrors Support's `OpenThread` and Android's `OpenPost`.
@MainActor
enum OpenPost {
  static var postId: String?
}
