import UIKit

/// One masked frame of the foreground scene, two pixels per screen point.
@MainActor
enum ReplayCapture {
  struct Frame {
    let image: UIImage
    /// Pixels, even on both axes as H.264 requires.
    let width: Int
    let height: Int
  }

  static func frame(rules: ReplayMaskRules) -> Frame? {
    guard let scene = foregroundScene(), let key = scene.keyWindow ?? scene.windows.first else { return nil }
    let bounds = key.bounds
    // Never past the screen's own pixels: upscaling would only cost bytes.
    let scale = min(ReplayLimits.captureScale, key.screen.scale)
    let width = evenPixels(bounds.width * scale)
    let height = evenPixels(bounds.height * scale)
    guard width >= 2, height >= 2 else { return nil }
    let scaleX = CGFloat(width) / bounds.width
    let scaleY = CGFloat(height) / bounds.height

    // The keyboard is left out: its key previews spell what is being typed.
    let windows = scene.windows
      .filter { !$0.isHidden && $0.alpha > 0.01 && !isKeyboard($0) }
      .sorted { $0.windowLevel < $1.windowLevel }

    guard let context = bitmapContext(width: width, height: height) else { return nil }
    UIGraphicsPushContext(context)
    for window in windows {
      let origin = CGPoint(
        x: (window.frame.minX - key.frame.minX) * scaleX,
        y: (window.frame.minY - key.frame.minY) * scaleY)
      window.drawHierarchy(
        in: CGRect(origin: origin, size: CGSize(
          width: window.bounds.width * scaleX, height: window.bounds.height * scaleY)),
        afterScreenUpdates: false)
      // Painted per window, before the next one is drawn over it.
      var rects = ReplayMasker.maskRects(in: window, rules: rules)
      if window === key { rects += ReplayMasker.bridgedRects ?? [] }
      let frames = rects.map {
        CGRect(
          x: origin.x + $0.minX * scaleX, y: origin.y + $0.minY * scaleY,
          width: $0.width * scaleX, height: $0.height * scaleY).integral
      }
      ReplayMaskStyle.paint(frames, in: context, pixelsPerPoint: scaleX)
    }
    UIGraphicsPopContext()
    guard let cgImage = context.makeImage() else { return nil }
    let image = UIImage(cgImage: cgImage)
    return Frame(image: image, width: width, height: height)
  }

  /// A plain bitmap, not `UIGraphicsImageRenderer`: the masks read its pixels,
  /// and a renderer's context exposes none. Flipped like UIKit, so memory row
  /// y is UIKit y.
  nonisolated static func bitmapContext(width: Int, height: Int) -> CGContext? {
    guard let context = CGContext(
      data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0,
      space: CGColorSpaceCreateDeviceRGB(),
      bitmapInfo: CGImageAlphaInfo.noneSkipFirst.rawValue | CGBitmapInfo.byteOrder32Little.rawValue)
    else { return nil }
    context.translateBy(x: 0, y: CGFloat(height))
    context.scaleBy(x: 1, y: -1)
    return context
  }

  static func keyWindow() -> UIWindow? {
    guard let scene = foregroundScene() else { return nil }
    return scene.keyWindow ?? scene.windows.first
  }

  static func evenPixels(_ value: CGFloat) -> Int {
    Int(value.rounded(.down)) / 2 * 2
  }

  private static func foregroundScene() -> UIWindowScene? {
    UIApplication.shared.connectedScenes
      .compactMap { $0 as? UIWindowScene }
      .first { $0.activationState == .foregroundActive }
  }

  private static func isKeyboard(_ window: UIWindow) -> Bool {
    let name = NSStringFromClass(type(of: window))
    return name.contains("Keyboard") || name.contains("TextEffects")
  }
}
