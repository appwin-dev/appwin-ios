import SwiftUI
import AppwinCore

/// Shown in place of the messenger while the studio's subscription is paused.
///
/// The pause's title and message and nothing else: no button, no retry, no
/// debug card (a pause is not an integration error), and no call to the
/// server. The way out is the host's container, or the cross when the
/// messenger was presented as a sheet.
struct SupportPausedView: View {
  let pause: AppwinPause
  var onClose: (() -> Void)?

  private let theme = AppwinTheme()

  /// The server's text, or the SDK's own for whichever part it left empty.
  static func copy(for pause: AppwinPause) -> (title: String, message: String) {
    (
      pause.title.isEmpty ? SupportStrings.pausedTitle : pause.title,
      pause.message.isEmpty ? SupportStrings.pausedMessage : pause.message
    )
  }

  var body: some View {
    let copy = Self.copy(for: pause)
    ZStack(alignment: .topTrailing) {
      theme.colors.background.ignoresSafeArea()
      VStack(spacing: theme.spacing.md) {
        Text(copy.title)
          .font(theme.fonts.title)
          .foregroundStyle(theme.colors.textPrimary)
        Text(copy.message)
          .font(theme.fonts.body)
          .foregroundStyle(theme.colors.textSecondary)
          .fixedSize(horizontal: false, vertical: true)
      }
      .multilineTextAlignment(.center)
      .frame(maxWidth: 340)
      .padding(.horizontal, theme.spacing.xl)
      .frame(maxWidth: .infinity, maxHeight: .infinity)
      if let onClose {
        Button(action: onClose) {
          Image(systemName: "xmark")
            .font(.system(size: 15, weight: .semibold))
            .foregroundStyle(theme.colors.textSecondary)
            .frame(width: 44, height: 44)
        }
        .accessibilityLabel(SupportStrings.close)
        .padding(.trailing, theme.spacing.sm)
      }
    }
  }
}
