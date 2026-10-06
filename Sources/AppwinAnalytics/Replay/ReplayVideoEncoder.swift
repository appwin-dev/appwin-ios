import AVFoundation
import CoreGraphics
import CoreVideo
import Foundation

/// Encodes still frames into an H.264 MP4 (ADR-0057): hardware encoder,
/// bitrate capped, a keyframe at least every ten frames. Synchronous: run it
/// off the main thread.
enum ReplayVideoEncoder {
  struct Frame {
    /// Milliseconds since the segment start.
    let offsetMs: Int
    let image: CGImage
  }

  enum Failure: Error {
    /// The writer could not start: this device does not record (no image
    /// fallback, ADR-0057).
    case unavailable(String)
    case failed(String)
  }

  static func encode(_ frames: [Frame], width: Int, height: Int, to url: URL) throws {
    guard let last = frames.last else { throw Failure.failed("no frame") }
    try? FileManager.default.removeItem(at: url)
    let writer: AVAssetWriter
    do {
      writer = try AVAssetWriter(outputURL: url, fileType: .mp4)
    } catch {
      throw Failure.unavailable("\(error)")
    }
    let input = AVAssetWriterInput(mediaType: .video, outputSettings: [
      AVVideoCodecKey: AVVideoCodecType.h264,
      AVVideoWidthKey: width,
      AVVideoHeightKey: height,
      AVVideoCompressionPropertiesKey: [
        AVVideoAverageBitRateKey: ReplayLimits.videoBitrate,
        AVVideoMaxKeyFrameIntervalKey: ReplayLimits.keyFrameInterval,
        // High rather than Baseline: same bitrate, much sharper text.
        AVVideoProfileLevelKey: AVVideoProfileLevelH264HighAutoLevel,
        AVVideoAllowFrameReorderingKey: false,
      ],
    ])
    input.expectsMediaDataInRealTime = false
    let adaptor = AVAssetWriterInputPixelBufferAdaptor(
      assetWriterInput: input,
      sourcePixelBufferAttributes: [
        kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA,
        kCVPixelBufferWidthKey as String: width,
        kCVPixelBufferHeightKey as String: height,
      ])
    guard writer.canAdd(input) else { throw Failure.unavailable("cannot add the video input") }
    writer.add(input)
    guard writer.startWriting() else {
      throw Failure.unavailable(writer.error.map { "\($0)" } ?? "startWriting failed")
    }
    writer.startSession(atSourceTime: .zero)

    for frame in frames {
      while !input.isReadyForMoreMediaData {
        if writer.status == .failed { break }
        Thread.sleep(forTimeInterval: 0.005)
      }
      guard writer.status == .writing,
            let buffer = pixelBuffer(frame.image, pool: adaptor.pixelBufferPool, width: width, height: height),
            adaptor.append(buffer, withPresentationTime: CMTime(value: Int64(frame.offsetMs), timescale: 1000))
      else {
        writer.cancelWriting()
        throw Failure.failed(writer.error.map { "\($0)" } ?? "append failed")
      }
    }
    input.markAsFinished()
    // The last frame lasts one capture interval.
    writer.endSession(atSourceTime: CMTime(
      value: Int64(last.offsetMs) + Int64(ReplayLimits.frameInterval * 1000), timescale: 1000))
    let done = DispatchSemaphore(value: 0)
    writer.finishWriting { done.signal() }
    done.wait()
    guard writer.status == .completed else {
      throw Failure.failed(writer.error.map { "\($0)" } ?? "finishWriting failed")
    }
  }

  private static func pixelBuffer(
    _ image: CGImage, pool: CVPixelBufferPool?, width: Int, height: Int
  ) -> CVPixelBuffer? {
    var buffer: CVPixelBuffer?
    if let pool {
      CVPixelBufferPoolCreatePixelBuffer(nil, pool, &buffer)
    } else {
      CVPixelBufferCreate(nil, width, height, kCVPixelFormatType_32BGRA, nil, &buffer)
    }
    guard let buffer else { return nil }
    CVPixelBufferLockBaseAddress(buffer, [])
    defer { CVPixelBufferUnlockBaseAddress(buffer, []) }
    guard let context = CGContext(
      data: CVPixelBufferGetBaseAddress(buffer),
      width: width, height: height, bitsPerComponent: 8,
      bytesPerRow: CVPixelBufferGetBytesPerRow(buffer),
      space: CGColorSpaceCreateDeviceRGB(),
      bitmapInfo: CGImageAlphaInfo.noneSkipFirst.rawValue | CGBitmapInfo.byteOrder32Little.rawValue)
    else { return nil }
    context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
    return buffer
  }
}
