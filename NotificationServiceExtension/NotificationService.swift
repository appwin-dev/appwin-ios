import UserNotifications
import UniformTypeIdentifiers

/// Rich push handler for Appwin campaigns.
///
/// Add this file to a **Notification Service Extension** target in the host app
/// (bundle id: `{AppBundleId}.NotificationService`). The server sends `imageUrl`
/// in the APNs payload when a campaign includes an image.
final class NotificationService: UNNotificationServiceExtension {
  private var contentHandler: ((UNNotificationContent) -> Void)?
  private var bestAttempt: UNMutableNotificationContent?

  override func didReceive(
    _ request: UNNotificationRequest,
    withContentHandler contentHandler: @escaping (UNNotificationContent) -> Void
  ) {
    self.contentHandler = contentHandler
    guard let mutable = request.content.mutableCopy() as? UNMutableNotificationContent else {
      contentHandler(request.content)
      return
    }
    bestAttempt = mutable

    guard let imageUrlString = Self.extractImageUrl(from: request.content.userInfo),
          let url = URL(string: imageUrlString) else {
      contentHandler(mutable)
      return
    }

    downloadAttachment(from: url) { [weak self] attachment in
      if let attachment {
        mutable.attachments = [attachment]
      }
      self?.contentHandler?(mutable)
    }
  }

  override func serviceExtensionTimeWillExpire() {
    if let contentHandler, let bestAttempt {
      contentHandler(bestAttempt)
    }
  }

  /// APNs puts custom keys at the root; FCM may nest them under `data`.
  private static func extractImageUrl(from userInfo: [AnyHashable: Any]) -> String? {
    if let direct = userInfo["imageUrl"] as? String, !direct.isEmpty {
      return direct
    }
    if let data = userInfo["data"] as? [AnyHashable: Any],
       let nested = data["imageUrl"] as? String,
       !nested.isEmpty {
      return nested
    }
    return nil
  }

  private func downloadAttachment(
    from url: URL,
    completion: @escaping (UNNotificationAttachment?) -> Void
  ) {
    let task = URLSession.shared.downloadTask(with: url) { location, response, _ in
      guard let location else {
        completion(nil)
        return
      }

      let ext = Self.fileExtension(for: response, fallbackURL: url)
      let tmp = URL(fileURLWithPath: NSTemporaryDirectory())
        .appendingPathComponent(UUID().uuidString)
        .appendingPathExtension(ext)

      do {
        try FileManager.default.moveItem(at: location, to: tmp)
        let attachment = try UNNotificationAttachment(
          identifier: "image",
          url: tmp,
          options: nil
        )
        completion(attachment)
      } catch {
        completion(nil)
      }
    }
    task.resume()
  }

  private static func fileExtension(for response: URLResponse?, fallbackURL: URL) -> String {
    if let mime = response?.mimeType,
       let utType = UTType(mimeType: mime),
       let preferred = utType.preferredFilenameExtension {
      return preferred
    }

    if let responseURL = response?.url, !responseURL.pathExtension.isEmpty {
      return responseURL.pathExtension
    }

    if !fallbackURL.pathExtension.isEmpty {
      return fallbackURL.pathExtension
    }

    return "jpg"
  }
}
