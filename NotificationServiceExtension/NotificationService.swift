import UserNotifications

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

    guard let imageUrlString = request.content.userInfo["imageUrl"] as? String,
          let url = URL(string: imageUrlString) else {
      contentHandler(mutable)
      return
    }

    downloadAttachment(from: url) { attachment in
      if let attachment {
        mutable.attachments = [attachment]
      }
      contentHandler(mutable)
    }
  }

  override func serviceExtensionTimeWillExpire() {
    if let contentHandler, let bestAttempt {
      contentHandler(bestAttempt)
    }
  }

  private func downloadAttachment(
    from url: URL,
    completion: @escaping (UNNotificationAttachment?) -> Void
  ) {
    URLSession.shared.downloadTask(with: url) { location, _, _ in
      guard let location else {
        completion(nil)
        return
      }
      let ext = url.pathExtension.isEmpty ? "jpg" : url.pathExtension
      let tmp = URL(fileURLWithPath: NSTemporaryDirectory())
        .appendingPathComponent(UUID().uuidString)
        .appendingPathExtension(ext)
      do {
        try FileManager.default.moveItem(at: location, to: tmp)
        completion(try UNNotificationAttachment(identifier: "image", url: tmp, options: nil))
      } catch {
        completion(nil)
      }
    }.resume()
  }
}
