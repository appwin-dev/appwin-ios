import SwiftUI
import UIKit

enum AppwinMaskFlag {
  case mask
  case unmask
}

nonisolated(unsafe) private var maskFlagKey: UInt8 = 0

extension UIView {
  /// Paints this view and everything inside it over in session replays,
  /// whatever the replay settings say.
  public func appwinMask() {
    appwinMaskFlag = .mask
  }

  /// Shows this view and its subviews in session replays even when the
  /// settings mask all text or images, and shows a web view, masked
  /// otherwise. Text inputs stay masked, always.
  public func appwinUnmask() {
    appwinMaskFlag = .unmask
  }

  var appwinMaskFlag: AppwinMaskFlag? {
    get { objc_getAssociatedObject(self, &maskFlagKey) as? AppwinMaskFlag }
    set { objc_setAssociatedObject(self, &maskFlagKey, newValue, .OBJC_ASSOCIATION_RETAIN_NONATOMIC) }
  }
}

extension View {
  /// Paints this view over in session replays, whatever the replay settings
  /// say.
  public func appwinMask() -> some View {
    overlay(AppwinMaskMarker(flag: .mask).allowsHitTesting(false).accessibilityHidden(true))
  }

  /// Shows this view in session replays even when the settings mask all text
  /// or images, and shows a web view, masked otherwise. Text inputs stay
  /// masked, always.
  public func appwinUnmask() -> some View {
    overlay(AppwinMaskMarker(flag: .unmask).allowsHitTesting(false).accessibilityHidden(true))
  }
}

/// A transparent UIView laid over the modified SwiftUI view: SwiftUI content
/// has no UIView of its own to flag, so the replay masker reads the marker's
/// frame instead.
final class AppwinMaskMarkerView: UIView {
  override init(frame: CGRect) {
    super.init(frame: frame)
    isUserInteractionEnabled = false
    backgroundColor = .clear
  }

  required init?(coder: NSCoder) { nil }
}

private struct AppwinMaskMarker: UIViewRepresentable {
  let flag: AppwinMaskFlag

  func makeUIView(context: Context) -> AppwinMaskMarkerView {
    let view = AppwinMaskMarkerView()
    view.appwinMaskFlag = flag
    return view
  }

  func updateUIView(_ view: AppwinMaskMarkerView, context: Context) {
    view.appwinMaskFlag = flag
  }
}
