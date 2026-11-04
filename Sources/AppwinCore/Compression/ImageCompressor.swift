// ImageCompressor - resize and recompress before upload (ADR-0023).
//
// Takes a 12 MB HEIC iPhone photo down to roughly 250 KB of JPEG, a 30x to 50x
// saving on mobile uploads. On by default in `AppwinCore.uploadMedia`.

import Foundation
import ImageIO
import UIKit
import UniformTypeIdentifiers

/// Compression options. The defaults target a good quality/size ratio for chat
/// (ADR-0023).
public struct MediaCompressionOptions: Sendable {
  /// Longest side after resize, in pixels. Aspect ratio is preserved.
  public let maxDimension: CGFloat
  /// JPEG quality. 0.8 is the industry default: indistinguishable by eye on
  /// natural photos, and around 70% smaller than 1.0.
  public let jpegQuality: CGFloat
  /// Convert HEIC/HEIF to JPEG for universal compatibility with old browsers
  /// and backends without HEIF support.
  public let convertHeicToJpeg: Bool

  public init(
    maxDimension: CGFloat = 1600,
    jpegQuality: CGFloat = 0.8,
    convertHeicToJpeg: Bool = true
  ) {
    self.maxDimension = maxDimension
    self.jpegQuality = jpegQuality
    self.convertHeicToJpeg = convertHeicToJpeg
  }

  public static let `default` = MediaCompressionOptions()
}

/// The caller can catch these and fall back to the original bytes by retrying
/// with `compression: nil`.
public enum ImageCompressionError: Error {
  case unsupportedFormat(String)
  case decodingFailed
  case encodingFailed
}

public enum ImageCompressor {
  /// MIME types treated as compressible images. Everything else passes
  /// through uploadMedia untouched.
  private static let imageMimes: Set<String> = [
    "image/jpeg",
    "image/png",
    "image/heic",
    "image/heif",
    "image/webp",
  ]

  public static func isImageMime(_ mime: String) -> Bool {
    imageMimes.contains(mime.lowercased())
  }

  /// Resizes and recompresses. Returns the upload-ready bytes and the
  /// effective mime type, which can differ from the input when HEIC or PNG is
  /// converted to JPEG.
  ///
  /// EXIF orientation is applied **before** the resize, or the photo comes out
  /// rotated. The rest of the EXIF metadata is deliberately stripped.
  ///
  /// - Throws: `ImageCompressionError` when the format cannot be decoded.
  @MainActor
  public static func compress(
    data: Data,
    inputMimeType: String,
    options: MediaCompressionOptions = .default
  ) async throws -> (data: Data, mimeType: String) {
    guard isImageMime(inputMimeType) else {
      throw ImageCompressionError.unsupportedFormat(inputMimeType)
    }

    // CGImageSource rather than UIImage(data:), which would decode the whole
    // bitmap into RAM.
    guard let source = CGImageSourceCreateWithData(data as CFData, nil) else {
      throw ImageCompressionError.decodingFailed
    }

    // The native thumbnail path decodes progressively and never loads the
    // full-size bitmap, which matters on 12+ MP photos.
    let thumbnailOptions: [CFString: Any] = [
      kCGImageSourceCreateThumbnailFromImageAlways: true,
      kCGImageSourceCreateThumbnailWithTransform: true, // applies EXIF orientation
      kCGImageSourceShouldCacheImmediately: true,
      kCGImageSourceThumbnailMaxPixelSize: options.maxDimension,
    ]
    guard let thumbnail = CGImageSourceCreateThumbnailAtIndex(
      source, 0, thumbnailOptions as CFDictionary
    ) else {
      throw ImageCompressionError.decodingFailed
    }

    // JPEG on the way out, for maximum compatibility: HEIC is not supported
    // everywhere, and PNG is larger on natural photos.
    let outputType: String = {
      if options.convertHeicToJpeg {
        return UTType.jpeg.identifier
      }
      // Conversion disabled: keep HEIC for HEIC, JPEG for the rest.
      return inputMimeType == "image/heic" ? UTType.heic.identifier : UTType.jpeg.identifier
    }()

    let outputMime: String = {
      if outputType == UTType.heic.identifier { return "image/heic" }
      return "image/jpeg"
    }()

    let outputData = NSMutableData()
    guard let destination = CGImageDestinationCreateWithData(
      outputData as CFMutableData,
      outputType as CFString,
      1,
      nil
    ) else {
      throw ImageCompressionError.encodingFailed
    }

    let destProperties: [CFString: Any] = [
      kCGImageDestinationLossyCompressionQuality: options.jpegQuality,
    ]
    CGImageDestinationAddImage(destination, thumbnail, destProperties as CFDictionary)
    guard CGImageDestinationFinalize(destination) else {
      throw ImageCompressionError.encodingFailed
    }

    return (data: outputData as Data, mimeType: outputMime)
  }
}
