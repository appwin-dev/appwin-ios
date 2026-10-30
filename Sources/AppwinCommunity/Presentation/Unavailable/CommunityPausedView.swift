import SwiftUI
import AppwinCore

/// Shown in place of the feed while the studio's subscription is paused.
///
/// The "opens soon" look, with the pause's title and message and nothing else:
/// no button, no retry, no debug card (a pause is not an integration error).
/// The way out is the host's container: the tab, or the close button of
/// `presentCommunity()`.
struct CommunityPausedView: View {
    let pause: AppwinPause
    var onClose: (() -> Void)?

    private let theme = CommunityTheme(config: .defaults)

    /// The server's text, or the SDK's own for whichever part it left empty.
    static func copy(for pause: AppwinPause) -> (title: String, message: String) {
        (
            pause.title.isEmpty ? CommunityStrings.pausedTitle : pause.title,
            pause.message.isEmpty ? CommunityStrings.pausedMessage : pause.message
        )
    }

    var body: some View {
        let copy = Self.copy(for: pause)
        ZStack(alignment: .topTrailing) {
            AppwinCommunityPalette.background.ignoresSafeArea()
            GeometryReader { proxy in
                ScrollView {
                    VStack(spacing: 0) {
                        CommunityUnavailableIllustration(theme: theme)
                        Text(copy.title)
                            .font(theme.font(22, weight: .bold))
                            .foregroundStyle(AppwinCommunityPalette.textPrimary)
                            .multilineTextAlignment(.center)
                            .padding(.top, 32)
                        Text(copy.message)
                            .font(theme.font(15))
                            .foregroundStyle(AppwinCommunityPalette.grey500)
                            .multilineTextAlignment(.center)
                            .lineSpacing(3)
                            .fixedSize(horizontal: false, vertical: true)
                            .padding(.top, 8)
                    }
                    .frame(maxWidth: 340)
                    .padding(.horizontal, 24)
                    .frame(maxWidth: .infinity, minHeight: proxy.size.height)
                }
            }
            if let onClose {
                Button(action: onClose) {
                    Image(systemName: "xmark")
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(AppwinCommunityPalette.grey500)
                        .frame(width: 44, height: 44)
                }
                .accessibilityLabel(CommunityStrings.close)
                .padding(.trailing, 8)
            }
        }
        .communityThemed(config: .defaults)
    }
}
