import UIKit

/// Which parts of the screen are painted over before a frame is encoded
/// (ADR-0057), from the project settings. Text inputs are masked whatever
/// they say, and web views unless unmasked.
struct ReplayMaskRules: Sendable, Equatable {
  var maskAllText: Bool
  var maskAllImages: Bool
}

/// Walks a view hierarchy and returns the rectangles to paint over, in the
/// coordinate space of the root.
///
/// Classification is by type first, then by class name for what this module
/// cannot import: React Native views (UIKit underneath) and SwiftUI's private
/// renderers. SwiftUI `Text` has no UIView of its own: it is drawn by a
/// `SwiftUI.CGDrawingView` (checked on iOS 26), a private class whose name may
/// change with an OS release: a studio that cannot afford a miss keeps
/// `maskAllText` on.
@MainActor
enum ReplayMasker {
  enum Kind: Equatable {
    case input
    case text
    case image
    /// A surface this walk cannot see into (`WKWebView`): its form fields
    /// cannot be told apart, so it is masked whole unless unmasked.
    case webView
  }

  private static let inputClassNames = [
    "RCTUITextField", "RCTUITextView", "RCTTextInputComponentView",
    "RCTSinglelineTextInputView", "RCTMultilineTextInputView",
  ]
  private static let textClassNames = ["RCTTextView", "RCTParagraphComponentView", "CGDrawingView"]
  private static let imageClassNames = ["RCTImageView", "RCTImageComponentView"]
  private static let webViewClassNames = ["WKWebView"]

  /// What the Flutter plugin reports Flutter drew there, in key window
  /// points (`setReplayBridgedMasks`). `nil` until its first report, and
  /// once the last one is older than `bridgedMaxAge`: the plugin resends
  /// every second, so silence means its view of the screen may be stale.
  static var bridgedRects: [CGRect]? {
    get {
      guard let bridged, Date().timeIntervalSince(bridged.at) <= bridgedMaxAge else { return nil }
      return bridged.rects
    }
    set { bridged = newValue.map { ($0, Date()) } }
  }

  static let bridgedMaxAge: TimeInterval = 2.5
  private static var bridged: (rects: [CGRect], at: Date)?

  static func maskRects(in root: UIView, rules: ReplayMaskRules) -> [CGRect] {
    var candidates: [(rect: CGRect, kind: Kind)] = []
    var explicitMasks: [CGRect] = []
    var unmaskRegions: [CGRect] = []
    collect(
      root, root: root, clip: root.bounds, unmasked: false,
      candidates: &candidates, explicitMasks: &explicitMasks, unmaskRegions: &unmaskRegions)

    var rects = explicitMasks
    for candidate in candidates {
      switch candidate.kind {
      case .input:
        rects.append(candidate.rect)
      case .text, .webView, .image:
        let enabled = switch candidate.kind {
        case .image: rules.maskAllImages
        case .text: rules.maskAllText
        default: true
        }
        // SwiftUI content has no UIView to flag, so `.appwinUnmask()` works by
        // region: whatever lies inside the marker's frame is spared.
        let spared = unmaskRegions.contains { $0.insetBy(dx: -1, dy: -1).contains(candidate.rect) }
        if enabled && !spared { rects.append(candidate.rect) }
      }
    }
    return rects
  }

  static func kind(of view: UIView) -> Kind? {
    if view is UITextField { return .input }
    if let textView = view as? UITextView { return textView.isEditable ? .input : .text }
    let name = NSStringFromClass(type(of: view))
    if inputClassNames.contains(where: name.contains) { return .input }
    if name.contains("FlutterView") {
      // The walk finds no text in there. Unless the Flutter plugin reports
      // what it drew, nothing of the surface may show, whatever the rules.
      return bridgedRects == nil ? .input : nil
    }
    if view is UILabel || textClassNames.contains(where: name.contains) { return .text }
    if view is UIImageView || imageClassNames.contains(where: name.contains) { return .image }
    if webViewClassNames.contains(where: name.contains) { return .webView }
    // SwiftUI draws a bitmap `Image` as the layer contents of a private view;
    // a plain color fill has none, so this spares backgrounds and shapes.
    if name.contains("SwiftUI"), let contents = view.layer.contents,
       CFGetTypeID(contents as CFTypeRef) == CGImage.typeID {
      return .image
    }
    return nil
  }

  private static func collect(
    _ view: UIView, root: UIView, clip: CGRect, unmasked: Bool,
    candidates: inout [(rect: CGRect, kind: Kind)],
    explicitMasks: inout [CGRect],
    unmaskRegions: inout [CGRect]
  ) {
    guard !view.isHidden, view.alpha > 0.01 else { return }
    let frame = view === root ? root.bounds : view.convert(view.bounds, to: root)
    let visible = frame.intersection(clip)
    let childClip = view.clipsToBounds ? visible : clip
    if visible.isNull || visible.isEmpty {
      // A view outside its clip can still have visible children unless it clips.
      if view.clipsToBounds { return }
    }

    let flag = view.appwinMaskFlag
    let kind = view === root ? nil : kind(of: view)
    if kind == .input {
      if !visible.isEmpty { candidates.append((visible, .input)) }
      return
    }
    if flag == .mask {
      if !visible.isEmpty { explicitMasks.append(visible) }
      return
    }
    let isUnmasked = unmasked || flag == .unmask
    if view is AppwinMaskMarkerView, flag == .unmask, !visible.isEmpty {
      unmaskRegions.append(visible)
    }
    if let kind, !isUnmasked, !visible.isEmpty {
      candidates.append((visible, kind))
      // The whole frame is painted: what is inside does not matter, except
      // inputs, which a text container may hold and which no unmask spares.
      if kind != .image { return collectInputsOnly(view, root: root, clip: childClip, into: &candidates) }
    }
    for subview in view.subviews {
      collect(
        subview, root: root, clip: childClip, unmasked: isUnmasked,
        candidates: &candidates, explicitMasks: &explicitMasks, unmaskRegions: &unmaskRegions)
    }
  }

  private static func collectInputsOnly(
    _ view: UIView, root: UIView, clip: CGRect, into candidates: inout [(rect: CGRect, kind: Kind)]
  ) {
    for subview in view.subviews where !subview.isHidden && subview.alpha > 0.01 {
      let visible = subview.convert(subview.bounds, to: root).intersection(clip)
      if kind(of: subview) == .input {
        if !visible.isEmpty { candidates.append((visible, .input)) }
      } else {
        collectInputsOnly(subview, root: root, clip: subview.clipsToBounds ? visible : clip, into: &candidates)
      }
    }
  }
}
