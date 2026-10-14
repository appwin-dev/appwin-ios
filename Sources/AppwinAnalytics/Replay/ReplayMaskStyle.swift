import CoreGraphics

/// How a mask looks: a rounded block in the average color of what it covers,
/// nudged off it so it still reads as a mask. Blends into the screen like a
/// loading skeleton; one color per block gives nothing away.
enum ReplayMaskStyle {
  /// In points: scaled to the frame's pixels so a mask looks the same at any capture size.
  static let cornerRadius: CGFloat = 6

  /// All colors are read before the first block is painted: overlapping masks
  /// must not sample each other.
  static func paint(_ rects: [CGRect], in context: CGContext, pixelsPerPoint: CGFloat = 1) {
    let bounds = CGRect(x: 0, y: 0, width: context.width, height: context.height)
    // The samples are in the context's space: a color from another one would
    // be converted on the way back and drift off the surface.
    let space = context.colorSpace ?? CGColorSpaceCreateDeviceRGB()
    let blocks = rects.compactMap { rect -> (CGRect, CGColor)? in
      let clipped = rect.intersection(bounds)
      guard !clipped.isEmpty else { return nil }
      return (clipped, blockColor(averageColor(of: clipped, in: context), space: space))
    }
    for (rect, color) in blocks {
      let radius = min(cornerRadius * pixelsPerPoint, rect.height / 2, rect.width / 2)
      context.setFillColor(color)
      context.addPath(CGPath(roundedRect: rect, cornerWidth: radius, cornerHeight: radius, transform: nil))
      context.fillPath()
    }
  }

  /// Darker on a light surface, lighter on a dark one.
  static func blockColor(_ rgb: (r: CGFloat, g: CGFloat, b: CGFloat), space: CGColorSpace) -> CGColor {
    let luminance = 0.299 * rgb.r + 0.587 * rgb.g + 0.114 * rgb.b
    let (target, amount): (CGFloat, CGFloat) = luminance > 0.5 ? (0, 0.1) : (1, 0.14)
    func mix(_ c: CGFloat) -> CGFloat { c + (target - c) * amount }
    let components = [mix(rgb.r), mix(rgb.g), mix(rgb.b), 1]
    return CGColor(colorSpace: space, components: components)
      ?? CGColor(red: components[0], green: components[1], blue: components[2], alpha: 1)
  }

  /// Up to 8 x 8 samples of the bitmap under [rect]; mid grey when the
  /// context's memory is not a 32-bit layout this reads.
  static func averageColor(of rect: CGRect, in context: CGContext) -> (r: CGFloat, g: CGFloat, b: CGFloat) {
    let fallback: (r: CGFloat, g: CGFloat, b: CGFloat) = (0.6, 0.6, 0.6)
    guard context.bitsPerPixel == 32, let data = context.data else { return fallback }
    let bytes = data.assumingMemoryBound(to: UInt8.self)
    let info = context.bitmapInfo
    let little = info.contains(.byteOrder32Little)
    let alpha = CGImageAlphaInfo(rawValue: info.rawValue & CGBitmapInfo.alphaInfoMask.rawValue)
    let alphaFirst = alpha == .first || alpha == .premultipliedFirst || alpha == .noneSkipFirst
    // Byte offsets of R, G, B in one pixel.
    let (ri, gi, bi): (Int, Int, Int) = switch (little, alphaFirst) {
    case (true, true): (2, 1, 0)   // BGRA in memory
    case (true, false): (3, 2, 1)  // ABGR
    case (false, true): (1, 2, 3)  // ARGB
    case (false, false): (0, 1, 2) // RGBA
    }
    let steps = 8
    var r = 0, g = 0, b = 0, n = 0
    for iy in 0..<steps {
      let y = Int(rect.minY + (rect.height - 1) * CGFloat(iy) / CGFloat(steps - 1))
      for ix in 0..<steps {
        let x = Int(rect.minX + (rect.width - 1) * CGFloat(ix) / CGFloat(steps - 1))
        guard x >= 0, y >= 0, x < context.width, y < context.height else { continue }
        let p = y * context.bytesPerRow + x * 4
        r += Int(bytes[p + ri]); g += Int(bytes[p + gi]); b += Int(bytes[p + bi]); n += 1
      }
    }
    guard n > 0 else { return fallback }
    let d = CGFloat(n) * 255
    return (CGFloat(r) / d, CGFloat(g) / d, CGFloat(b) / d)
  }
}
