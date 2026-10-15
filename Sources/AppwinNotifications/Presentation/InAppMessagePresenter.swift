import Foundation
import SwiftUI
import UIKit
import AppwinCore

/// Presents in-app messages one at a time over the host app.
@MainActor
final class InAppMessagePresenter {
  static let shared = InAppMessagePresenter()

  private var queue: [InAppMessage] = []
  private var isPresenting = false
  private var hostController: UIHostingController<AnyView>?
  /// Deliveries already shown or in flight — avoids re-fetch races while tracking is async.
  private var seenDeliveryIds = Set<String>()
  private var suppressNextAppOpen = false

  private init() {}

  var isShowingMessage: Bool { isPresenting }

  /// Call after closing an in-app message so the next lifecycle sync only fetches.
  func consumeSuppressNextAppOpen() -> Bool {
    defer { suppressNextAppOpen = false }
    return suppressNextAppOpen
  }

  func enqueue(_ messages: [InAppMessage]) {
    let unseen = messages.filter { message in
      !seenDeliveryIds.contains(message.deliveryId)
        && !queue.contains(where: { $0.deliveryId == message.deliveryId })
    }
    guard !unseen.isEmpty else { return }
    queue.append(contentsOf: unseen)
    presentNextIfNeeded()
  }

  func presentPending() {
    presentNextIfNeeded()
  }

  private func presentNextIfNeeded() {
    guard !isPresenting, !queue.isEmpty else { return }
    guard let presenter = topViewController() else { return }

    isPresenting = true
    let message = queue.removeFirst()
    seenDeliveryIds.insert(message.deliveryId)

    let view = InAppMessageView(message: message) { [weak self] action in
      self?.handleAction(action, for: message)
    }
    let controller = UIHostingController(rootView: AnyView(view))
    hostController = controller

    switch message.format {
    case .banner:
      controller.modalPresentationStyle = .overFullScreen
      controller.view.backgroundColor = .clear
    case .fullscreen, .imageOnly:
      controller.modalPresentationStyle = .fullScreen
    case .modal:
      controller.modalPresentationStyle = .overCurrentContext
      controller.view.backgroundColor = .clear
    }

    presenter.present(controller, animated: true) { [weak self] in
      Task {
        try? await AppwinNotifications.track(deliveryId: message.deliveryId, event: .opened)
      }
      _ = self
    }
  }

  private func handleAction(_ action: InAppMessageAction, for message: InAppMessage) {
    Task {
      switch action {
      case .primaryTap:
        try? await AppwinNotifications.track(deliveryId: message.deliveryId, event: .clicked)
        if let deeplink = message.content.deeplink, let url = URL(string: deeplink) {
          AppwinPush.openDeeplink(url)
        }
      case .button(let index, let button):
        try? await AppwinNotifications.track(
          deliveryId: message.deliveryId,
          event: .clicked,
          buttonIndex: index
        )
        await performButtonAction(button)
      case .dismiss:
        try? await AppwinNotifications.track(deliveryId: message.deliveryId, event: .dismissed)
      }
      dismissCurrent()
    }
  }

  private func performButtonAction(_ button: InAppButton) async {
    switch button.action {
    case .deeplink:
      if let urlString = button.url, let url = URL(string: urlString) {
        AppwinPush.openDeeplink(url)
      }
    case .dismiss:
      break
    case .optInPush:
      _ = try? await AppwinNotifications.requestPushAuthorization()
    case .openSettings:
      if let url = URL(string: UIApplication.openSettingsURLString) {
        await UIApplication.shared.open(url)
      }
    }
  }

  private func dismissCurrent() {
    hostController?.dismiss(animated: true) { [weak self] in
      self?.hostController = nil
      self?.isPresenting = false
      self?.suppressNextAppOpen = true
      self?.presentNextIfNeeded()
    }
  }

  private func topViewController() -> UIViewController? {
    let scene = UIApplication.shared.connectedScenes
      .compactMap { $0 as? UIWindowScene }
      .first { $0.activationState == .foregroundActive }
    guard var top = scene?.windows.first(where: \.isKeyWindow)?.rootViewController else {
      return nil
    }
    while let presented = top.presentedViewController {
      top = presented
    }
    return top
  }
}

enum InAppMessageAction {
  case primaryTap
  case button(index: Int, button: InAppButton)
  case dismiss
}
