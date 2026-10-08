import UIKit

/// One masked frame of the foreground scene, two pixels per screen point.
@MainActor
enum ReplayCapture {
  struct Frame {
    /// Pixels, even on both axes as H.264 requires.
    let width: Int
    let height: Int
    /// Run on the recorder's I/O queue: what is left to draw stays off the main thread.
    let render: @Sendable () -> UIImage?
  }

  /// A frame the Flutter plugin rendered on the engine's threads, where
  /// `drawHierarchy` would hold the main thread while the engine renders
  /// the screen again (about 150 ms on an iPhone 15, every second).
  struct BridgedFrame {
    /// RGBA, premultiplied, rows packed.
    let rgba: Data
    let width: Int
    let height: Int
    /// To paint over, in key window points, read from the same frame.
    let masks: [CGRect]
    let at: Date
    weak var surface: UIView?
  }

  /// One window's pixels and what to paint over them, in frame pixels.
  struct Layer: @unchecked Sendable {
    let image: CGImage
    let rect: CGRect
    let masks: [CGRect]
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

    // A renderer at the frame's scale, drawing in points: drawn into a
    // context sized in pixels instead, the window renders at the screen's
    // own scale and is shrunk after, 4.5 times the main thread for the same
    // pixels (161 ms against 36 ms, iPhone 15).
    var layers: [Layer] = []
    for (index, window) in windows.enumerated() {
      let format = UIGraphicsImageRendererFormat()
      format.scale = scaleX
      format.opaque = index == 0
      let image = UIGraphicsImageRenderer(bounds: window.bounds, format: format).image { _ in
        window.drawHierarchy(in: window.bounds, afterScreenUpdates: false)
      }
      guard let cgImage = image.cgImage else { continue }
      let origin = CGPoint(
        x: (window.frame.minX - key.frame.minX) * scaleX,
        y: (window.frame.minY - key.frame.minY) * scaleY)
      var rects = ReplayMasker.maskRects(in: window, rules: rules)
      if window === key { rects += ReplayMasker.bridgedRects ?? [] }
      let masks = rects.map {
        CGRect(
          x: origin.x + $0.minX * scaleX, y: origin.y + $0.minY * scaleY,
          width: $0.width * scaleX, height: $0.height * scaleY).integral
      }
      layers.append(Layer(
        image: cgImage,
        rect: CGRect(origin: origin, size: CGSize(
          width: window.bounds.width * scaleX, height: window.bounds.height * scaleY)),
        masks: masks))
    }
    guard !layers.isEmpty else { return nil }
    let drawn = layers
    return Frame(width: width, height: height, render: {
      compose(drawn, width: width, height: height, pixelsPerPoint: scaleX)
    })
  }

  /// The layers in order, each one's masks painted before the next is drawn
  /// over it. A plain bitmap, not a renderer: the masks read its pixels.
  nonisolated static func compose(
    _ layers: [Layer], width: Int, height: Int, pixelsPerPoint: CGFloat
  ) -> UIImage? {
    guard let context = bitmapContext(width: width, height: height) else { return nil }
    UIGraphicsPushContext(context)
    for layer in layers {
      // UIKit drawing: the context is flipped, a bare CGContext.draw would land upside down.
      UIImage(cgImage: layer.image).draw(in: layer.rect)
      ReplayMaskStyle.paint(layer.masks, in: context, pixelsPerPoint: pixelsPerPoint)
    }
    UIGraphicsPopContext()
    return context.makeImage().map(UIImage.init(cgImage:))
  }

  /// [bridged] at the size a native capture would have, masks painted.
  static func frame(bridged: BridgedFrame) -> Frame? {
    guard let key = keyWindow() else { return nil }
    let bounds = key.bounds
    let scale = min(ReplayLimits.captureScale, key.screen.scale)
    let width = evenPixels(bounds.width * scale)
    let height = evenPixels(bounds.height * scale)
    guard width >= 2, height >= 2, bridged.width > 0, bridged.height > 0,
          bridged.rgba.count >= bridged.width * bridged.height * 4
    else { return nil }
    let pixelsPerPoint = CGFloat(width) / bounds.width
    let (rgba, sourceWidth, sourceHeight, masks) = (bridged.rgba, bridged.width, bridged.height, bridged.masks)
    return Frame(width: width, height: height, render: {
      render(
        rgba: rgba, width: sourceWidth, height: sourceHeight, masks: masks,
        into: width, height, pixelsPerPoint: pixelsPerPoint)
    })
  }

  /// Flutter's pixels scaled to the frame size, masks painted over.
  nonisolated static func render(
    rgba: Data, width sourceWidth: Int, height sourceHeight: Int, masks: [CGRect],
    into width: Int, _ height: Int, pixelsPerPoint: CGFloat
  ) -> UIImage? {
    guard let provider = CGDataProvider(data: rgba as CFData),
          let image = CGImage(
            width: sourceWidth, height: sourceHeight, bitsPerComponent: 8, bitsPerPixel: 32,
            bytesPerRow: sourceWidth * 4, space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedLast.rawValue),
            provider: provider, decode: nil, shouldInterpolate: true, intent: .defaultIntent)
    else { return nil }
    let rects = masks.map {
      CGRect(
        x: $0.minX * pixelsPerPoint, y: $0.minY * pixelsPerPoint,
        width: $0.width * pixelsPerPoint, height: $0.height * pixelsPerPoint).integral
    }
    let layer = Layer(image: image, rect: CGRect(x: 0, y: 0, width: width, height: height), masks: rects)
    return compose([layer], width: width, height: height, pixelsPerPoint: pixelsPerPoint)
  }

  /// Whether [surface] is all the foreground scene shows: no other window
  /// but the keyboard, nothing laid over it, no native view inside it (a
  /// platform view). Only then is a frame rendered by Flutter alone the
  /// whole screen; otherwise the native capture runs.
  static func showsOnly(_ surface: UIView) -> Bool {
    guard let scene = foregroundScene(), let key = scene.keyWindow ?? scene.windows.first else { return false }
    return showsOnly(surface, key: key, windows: scene.windows)
  }

  static func showsOnly(_ surface: UIView, key: UIWindow, windows: [UIWindow]) -> Bool {
    guard surface.window === key, isVisible(surface),
          surface.convert(surface.bounds, to: key).insetBy(dx: -1, dy: -1).contains(key.bounds),
          !surface.subviews.contains(where: { isVisible($0) && !isFlutterTextInput($0) })
    else { return false }
    if windows.contains(where: { $0 !== key && isVisible($0) && !isKeyboard($0) }) { return false }
    var view = surface
    while let parent = view.superview {
      guard let index = parent.subviews.firstIndex(of: view) else { return false }
      if parent.subviews[(index + 1)...].contains(where: isVisible) { return false }
      view = parent
    }
    return true
  }

  private static func isVisible(_ view: UIView) -> Bool {
    !view.isHidden && view.alpha > 0.01 && !view.bounds.isEmpty
  }

  /// The engine's hidden host for the text being edited: the field itself is
  /// in Flutter's frame, and masked there.
  private static func isFlutterTextInput(_ view: UIView) -> Bool {
    NSStringFromClass(type(of: view)).contains("TextInput")
  }

  /// The bitmap masks are painted on: they read its pixels, which a
  /// renderer's context does not expose. Flipped like UIKit, so memory row
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
