import UIKit

/// One in-app notification.
///
/// `id` deduplicates: the same banner presented twice in a row is shown once.
/// `onTap` runs after the banner has been dismissed.
public struct AppwinBanner: Sendable {
  public let id: String
  public let title: String
  public let body: String
  /// Studio accent as `#RRGGBB`, used for the leading dot.
  public let accentHex: String?
  public let onTap: (@MainActor @Sendable () -> Void)?

  public init(
    id: String,
    title: String,
    body: String,
    accentHex: String? = nil,
    onTap: (@MainActor @Sendable () -> Void)? = nil
  ) {
    self.id = id
    self.title = title
    self.body = body
    self.accentHex = accentHex
    self.onTap = onTap
  }
}

/// The shared in-app notification surface, hosted by Core.
///
/// Support and Notifications are sibling targets that both depend on Core and
/// neither on the other, so neither can own a surface the other needs. Putting
/// the banner here is the same call already made for `RealtimeHub`: one
/// connection, one overlay, fed by whichever products the studio bought.
///
/// Drawn in UIKit rather than SwiftUI so it can be raised from anywhere -
/// including a realtime callback with no view in scope - and so it sits above
/// whatever the host app is presenting, sheets included.
///
/// Mirrors `AppwinInAppBanner` on Android.
@MainActor
public enum AppwinInAppBanner {

  /// Set by whichever product currently owns the screen.
  ///
  /// The messenger raises it while a thread is open: a banner announcing the
  /// message already visible underneath is noise.
  public static var isSuppressed = false

  private static var showing: UIView?
  private static var lastShownID: String?
  private static var dismissWork: DispatchWorkItem?

  /// Long enough to read two lines, short enough to forgive.
  private static let visibleDuration: TimeInterval = 5
  private static let animationDuration: TimeInterval = 0.28

  /// Shows `banner`, or drops it.
  ///
  /// Dropped when the app has no foreground window - it is in the background,
  /// and the push notification is what covers that case - when a product has
  /// suppressed the surface, or when the same banner is already on screen.
  public static func present(_ banner: AppwinBanner) {
    guard !isSuppressed else { return }
    guard banner.id != lastShownID || showing == nil else { return }
    guard let window = foregroundWindow() else { return }

    dismissNow()
    lastShownID = banner.id

    let card = makeCard(banner)
    showing = card
    window.addSubview(card)

    let top = card.topAnchor.constraint(
      equalTo: window.safeAreaLayoutGuide.topAnchor,
      constant: 8
    )
    NSLayoutConstraint.activate([
      card.leadingAnchor.constraint(equalTo: window.leadingAnchor, constant: 12),
      card.trailingAnchor.constraint(equalTo: window.trailingAnchor, constant: -12),
      top,
    ])
    window.layoutIfNeeded()

    // Off-screen first, then down: the height is only known once laid out.
    card.transform = CGAffineTransform(translationX: 0, y: -card.bounds.height - 24)
    card.alpha = 0
    UIView.animate(withDuration: animationDuration, delay: 0, options: [.curveEaseOut]) {
      card.transform = .identity
      card.alpha = 1
    }

    let work = DispatchWorkItem { dismiss() }
    dismissWork = work
    DispatchQueue.main.asyncAfter(deadline: .now() + visibleDuration, execute: work)
  }

  /// Slides the current banner away, if there is one.
  public static func dismiss() {
    dismissWork?.cancel()
    dismissWork = nil
    guard let card = showing else { return }
    showing = nil
    UIView.animate(
      withDuration: animationDuration,
      delay: 0,
      options: [.curveEaseIn],
      animations: {
        card.transform = CGAffineTransform(translationX: 0, y: -card.bounds.height - 24)
        card.alpha = 0
      },
      completion: { _ in card.removeFromSuperview() }
    )
  }

  private static func dismissNow() {
    dismissWork?.cancel()
    dismissWork = nil
    showing?.removeFromSuperview()
    showing = nil
  }

  // MARK: - View

  private static func makeCard(_ banner: AppwinBanner) -> UIView {
    let card = BannerView(banner: banner)
    card.translatesAutoresizingMaskIntoConstraints = false
    card.backgroundColor = .white
    card.layer.cornerRadius = 16
    card.layer.shadowColor = UIColor.black.cgColor
    card.layer.shadowOpacity = 0.12
    card.layer.shadowRadius = 12
    card.layer.shadowOffset = CGSize(width: 0, height: 4)

    let dot = UIView()
    dot.translatesAutoresizingMaskIntoConstraints = false
    dot.backgroundColor = parseHex(banner.accentHex) ?? UIColor(
      red: 0.58, green: 0.64, blue: 0.72, alpha: 1
    )
    dot.layer.cornerRadius = 4

    let title = UILabel()
    title.translatesAutoresizingMaskIntoConstraints = false
    title.text = banner.title
    title.font = .systemFont(ofSize: 13, weight: .semibold)
    title.textColor = UIColor(red: 0.05, green: 0.09, blue: 0.16, alpha: 1)
    title.numberOfLines = 1

    let body = UILabel()
    body.translatesAutoresizingMaskIntoConstraints = false
    body.text = banner.body
    body.font = .systemFont(ofSize: 13)
    body.textColor = UIColor(red: 0.20, green: 0.25, blue: 0.34, alpha: 1)
    body.numberOfLines = 2

    let column = UIStackView(arrangedSubviews: [title, body])
    column.translatesAutoresizingMaskIntoConstraints = false
    column.axis = .vertical
    column.spacing = 2

    card.addSubview(dot)
    card.addSubview(column)
    NSLayoutConstraint.activate([
      dot.widthAnchor.constraint(equalToConstant: 8),
      dot.heightAnchor.constraint(equalToConstant: 8),
      dot.leadingAnchor.constraint(equalTo: card.leadingAnchor, constant: 14),
      dot.centerYAnchor.constraint(equalTo: card.centerYAnchor),

      column.leadingAnchor.constraint(equalTo: dot.trailingAnchor, constant: 10),
      column.trailingAnchor.constraint(equalTo: card.trailingAnchor, constant: -14),
      column.topAnchor.constraint(equalTo: card.topAnchor, constant: 12),
      column.bottomAnchor.constraint(equalTo: card.bottomAnchor, constant: -12),
    ])

    card.addGestureRecognizer(
      UITapGestureRecognizer(target: card, action: #selector(BannerView.handleTap))
    )
    card.addGestureRecognizer(
      UIPanGestureRecognizer(target: card, action: #selector(BannerView.handlePan(_:)))
    )
    return card
  }

  /// The window the user is actually looking at.
  ///
  /// The *key* window alone is not enough: a host app presenting a sheet from
  /// its own window would take the banner off screen with it.
  private static func foregroundWindow() -> UIWindow? {
    UIApplication.shared.connectedScenes
      .compactMap { $0 as? UIWindowScene }
      .first { $0.activationState == .foregroundActive }?
      .windows
      .first { $0.isKeyWindow }
  }

  private static func parseHex(_ raw: String?) -> UIColor? {
    guard var hex = raw?.trimmingCharacters(in: .whitespacesAndNewlines) else { return nil }
    if hex.hasPrefix("#") { hex.removeFirst() }
    if hex.count == 3 { hex = hex.map { "\($0)\($0)" }.joined() }
    guard hex.count == 6, let value = UInt32(hex, radix: 16) else { return nil }
    return UIColor(
      red: CGFloat((value >> 16) & 0xFF) / 255,
      green: CGFloat((value >> 8) & 0xFF) / 255,
      blue: CGFloat(value & 0xFF) / 255,
      alpha: 1
    )
  }
}

/// Carries the banner so the gesture targets can reach `onTap` without a
/// closure stored on the enum.
@MainActor
private final class BannerView: UIView {
  private let banner: AppwinBanner

  init(banner: AppwinBanner) {
    self.banner = banner
    super.init(frame: .zero)
  }

  @available(*, unavailable)
  required init?(coder: NSCoder) { fatalError("not used") }

  @objc func handleTap() {
    AppwinInAppBanner.dismiss()
    banner.onTap?()
  }

  /// Drag upwards to dismiss; anything else springs back.
  @objc func handlePan(_ gesture: UIPanGestureRecognizer) {
    let dy = gesture.translation(in: self).y
    switch gesture.state {
    case .changed:
      transform = CGAffineTransform(translationX: 0, y: min(0, dy))
    case .ended, .cancelled:
      if dy < -32 {
        AppwinInAppBanner.dismiss()
      } else {
        UIView.animate(withDuration: 0.2) { self.transform = .identity }
      }
    default:
      break
    }
  }
}
