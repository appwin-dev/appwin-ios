import SwiftUI
import UIKit

// Screen chrome of the Figma InApp community frames.

/// Figma button/icon-native: translucent surface, soft halo, 20pt glyph.
struct CommunityGlassButton: View {
    let systemImage: String
    var accessibilityLabel: String
    let action: () -> Void

    @Environment(\.communityTheme) private var theme

    var body: some View {
        Button(action: action) {
            Image(systemName: systemImage)
                .font(.system(size: 17, weight: .medium))
                .foregroundStyle(theme.colors.textPrimary)
                .frame(width: 38, height: 38)
                .background(theme.colors.surface.opacity(0.56), in: Circle())
                .shadow(color: .black.opacity(0.12), radius: 20)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(accessibilityLabel)
    }
}

/// Figma header/default: a text action on the left ("Annuler", "Retour"), the
/// title centred, an optional control on the right.
struct CommunityNavHeader<Trailing: View>: View {
    let leadingTitle: String
    let onLeading: () -> Void
    let title: String
    var background: Color?
    var verticalPadding: CGFloat = 24
    @ViewBuilder var trailing: () -> Trailing

    @Environment(\.communityTheme) private var theme

    /// Same width on both sides so the title stays centred; wide enough for the
    /// "Enregistrer" pill.
    private static var sideWidth: CGFloat { 104 }

    var body: some View {
        // Baseline, as in Figma: the 14pt action and the 16pt title sit on one
        // line. The title is laid over the row rather than between two side
        // columns, so an absent trailing view cannot pull it off centre.
        ZStack(alignment: Alignment(horizontal: .center, vertical: .firstTextBaseline)) {
            Text(title)
                .font(theme.font(16, weight: .medium))
                .foregroundStyle(theme.colors.textPrimary)
                .lineLimit(1)
                .padding(.horizontal, Self.sideWidth)

            HStack(alignment: .firstTextBaseline, spacing: 0) {
                Button(action: onLeading) {
                    Text(leadingTitle)
                        .font(theme.font(14, weight: .medium))
                        .foregroundStyle(theme.colors.textTertiary)
                        .lineLimit(1)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .frame(maxWidth: Self.sideWidth, alignment: .leading)

                Spacer(minLength: 0)

                trailing()
                    .frame(maxWidth: Self.sideWidth, alignment: .trailing)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.horizontal, 16)
        .padding(.vertical, verticalPadding)
        .background(background ?? .clear)
    }
}

extension CommunityNavHeader where Trailing == EmptyView {
    init(
        leadingTitle: String,
        onLeading: @escaping () -> Void,
        title: String,
        background: Color? = nil,
        verticalPadding: CGFloat = 24
    ) {
        self.init(
            leadingTitle: leadingTitle,
            onLeading: onLeading,
            title: title,
            background: background,
            verticalPadding: verticalPadding,
            trailing: { EmptyView() }
        )
    }
}

/// Figma brand pill ("Publier", "Enregistrer"): the accent fill, onAccent text.
struct CommunityBrandPill: View {
    let title: String
    var icon: CommunityIcon?
    var fontSize: CGFloat = 16
    var isEnabled = true
    var isLoading = false
    let action: () -> Void

    @Environment(\.communityTheme) private var theme

    var body: some View {
        Button(action: action) {
            HStack(spacing: 8) {
                if isLoading {
                    ProgressView().tint(theme.colors.onAccent)
                } else if let icon {
                    CommunityIconView(icon: icon, size: 16, color: theme.colors.onAccent)
                }
                Text(title)
                    .font(theme.font(fontSize, weight: .semibold))
                    .lineLimit(1)
                    .fixedSize()
            }
            .foregroundStyle(theme.colors.onAccent)
            .padding(.horizontal, fontSize >= 16 ? 16 : 12)
            .padding(.vertical, fontSize >= 16 ? 12 : 8)
            .background(theme.composeFill, in: RoundedRectangle(cornerRadius: theme.radius.card))
            .opacity(isEnabled && !isLoading ? 1 : 0.5)
        }
        .buttonStyle(.plain)
        .disabled(!isEnabled || isLoading)
    }
}

/// Figma "light" (5:2153, 32:5960): a 320×240 ellipse of the accent at 24 %,
/// centred on the top-left corner of the feed header and the profile hero,
/// under a 40 px layer blur.
///
/// Figma's layer blur value is twice the Gaussian radius SwiftUI takes, hence
/// 20. A radial gradient inside the ellipse is not a substitute: it is still
/// at ~25 % where the shorter axis ends, which draws a hard crop.
struct CommunityAccentGlow: View {
    @Environment(\.communityTheme) private var theme

    var body: some View {
        Color.clear
            .overlay(alignment: .topLeading) {
                Ellipse()
                    .fill(theme.colors.accent.opacity(0.24))
                    .frame(width: 320, height: 240)
                    .blur(radius: 20)
                    .offset(x: -160, y: -120)
            }
            // A header without group filters is shorter than the glow: fade it
            // out before the bottom edge instead of cutting it there.
            .mask(
                LinearGradient(
                    stops: [.init(color: .black, location: 0.55), .init(color: .clear, location: 1)],
                    startPoint: .top,
                    endPoint: .bottom
                )
            )
            .allowsHitTesting(false)
    }
}

/// Re-enables the UIKit interactive pop (swipe from edge) when the system back
/// button is hidden, since hiding the bar disables it.
private struct CommunityInteractivePopGesture: UIViewControllerRepresentable {
    func makeCoordinator() -> Coordinator { Coordinator() }

    func makeUIViewController(context: Context) -> UIViewController { UIViewController() }

    func updateUIViewController(_ uiViewController: UIViewController, context: Context) {
        DispatchQueue.main.async {
            guard let nav = uiViewController.navigationController else { return }
            let gesture = nav.interactivePopGestureRecognizer
            gesture?.isEnabled = nav.viewControllers.count > 1
            gesture?.delegate = context.coordinator
            context.coordinator.navigationController = nav
        }
    }

    final class Coordinator: NSObject, UIGestureRecognizerDelegate {
        weak var navigationController: UINavigationController?

        func gestureRecognizerShouldBegin(_ gestureRecognizer: UIGestureRecognizer) -> Bool {
            (navigationController?.viewControllers.count ?? 0) > 1
        }

        func gestureRecognizer(
            _ gestureRecognizer: UIGestureRecognizer,
            shouldRecognizeSimultaneouslyWith otherGestureRecognizer: UIGestureRecognizer
        ) -> Bool {
            true
        }
    }
}

extension View {
    /// Apply to a pushed screen that draws its own back action.
    func communityInteractivePop() -> some View {
        background(CommunityInteractivePopGesture())
    }
}
