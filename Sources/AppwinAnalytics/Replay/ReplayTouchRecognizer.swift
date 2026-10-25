import UIKit
import UIKit.UIGestureRecognizerSubclass

/// Observes taps on a window without taking part in gesture recognition: it
/// never recognizes, cancels or delays anything, and fails once the fingers
/// lift. No swizzling of `sendEvent`.
final class ReplayTouchRecognizer: UIGestureRecognizer, UIGestureRecognizerDelegate {
  /// Tap location normalized to the window, 0...1 on both axes.
  var onTap: ((CGPoint) -> Void)?

  /// Further than this between down and up, it was a scroll, not a tap.
  private static let tapSlop: CGFloat = 20
  private var starts: [ObjectIdentifier: CGPoint] = [:]

  /// A finger is down on the window: the recorder holds its frames (`ReplayPacer`).
  var isTouching: Bool { !starts.isEmpty }
  private(set) var lastTouchAt: Date?

  init() {
    super.init(target: nil, action: nil)
    cancelsTouchesInView = false
    delaysTouchesBegan = false
    delaysTouchesEnded = false
    delegate = self
  }

  override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent) {
    lastTouchAt = Date()
    for touch in touches { starts[ObjectIdentifier(touch)] = touch.location(in: view) }
  }

  override func touchesEnded(_ touches: Set<UITouch>, with event: UIEvent) {
    lastTouchAt = Date()
    for touch in touches {
      guard let start = starts.removeValue(forKey: ObjectIdentifier(touch)), let view else { continue }
      let end = touch.location(in: view)
      guard hypot(end.x - start.x, end.y - start.y) <= Self.tapSlop,
            view.bounds.width > 0, view.bounds.height > 0
      else { continue }
      onTap?(CGPoint(
        x: min(max(end.x / view.bounds.width, 0), 1),
        y: min(max(end.y / view.bounds.height, 0), 1)))
    }
    if starts.isEmpty { state = .failed }
  }

  override func touchesCancelled(_ touches: Set<UITouch>, with event: UIEvent) {
    lastTouchAt = Date()
    for touch in touches { starts.removeValue(forKey: ObjectIdentifier(touch)) }
    if starts.isEmpty { state = .failed }
  }

  override func reset() {
    starts.removeAll()
  }

  func gestureRecognizer(
    _ gestureRecognizer: UIGestureRecognizer,
    shouldRecognizeSimultaneouslyWith other: UIGestureRecognizer
  ) -> Bool { true }
}
