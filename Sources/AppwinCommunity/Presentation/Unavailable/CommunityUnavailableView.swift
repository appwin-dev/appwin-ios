import SwiftUI
import AppwinCore

/// Shown in place of the feed while Community is not ready.
///
/// Painted from the SDK's own palette and the default theme, never from the
/// studio config: when this shows, no config has been loaded, and the studio
/// may not even have access to the product.
struct CommunityUnavailableView: View {
    let result: AppwinInitResult?
    var animatesEntrance = true

    @State private var appeared = false

    private let theme = CommunityTheme(config: .defaults)

    var body: some View {
        ZStack {
            AppwinCommunityPalette.background.ignoresSafeArea()

            // Centred when it fits, scrollable when the debug alert and a large
            // Dynamic Type size do not (iOS 16 has no `defaultScrollAnchor`).
            GeometryReader { proxy in
                ScrollView {
                    VStack(spacing: 0) {
                        #if DEBUG
                        if let diagnosis = CommunityDebugDiagnosis(result: result) {
                            CommunityDebugAlert(diagnosis: diagnosis, theme: theme)
                                .padding(.horizontal, 16)
                                .padding(.top, 12)
                        }
                        #endif
                        Spacer(minLength: 32)
                        content
                        Spacer(minLength: 32)
                    }
                    .frame(maxWidth: .infinity, minHeight: proxy.size.height)
                }
            }
        }
        .preferredColorScheme(.light)
        .onAppear {
            guard animatesEntrance, !appeared else { return }
            withAnimation(.easeOut(duration: 0.35)) { appeared = true }
        }
    }

    private var content: some View {
        VStack(spacing: 0) {
            illustration
            Text(CommunityStrings.unavailableTitle)
                .font(theme.font(22, weight: .bold))
                .foregroundStyle(AppwinCommunityPalette.textPrimary)
                .multilineTextAlignment(.center)
                .padding(.top, 32)
            Text(CommunityStrings.unavailableMessage)
                .font(theme.font(15))
                .foregroundStyle(AppwinCommunityPalette.grey500)
                .multilineTextAlignment(.center)
                .lineSpacing(3)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.top, 8)
        }
        .frame(maxWidth: 340)
        .padding(.horizontal, 24)
        .opacity(isShown ? 1 : 0)
        .offset(y: isShown ? 0 : 8)
    }

    private var isShown: Bool { !animatesEntrance || appeared }

    /// A feed still being set up: two blank posts, fanned out, under the
    /// community badge. Reads as "a space is coming" rather than "an error".
    private var illustration: some View {
        ZStack {
            Circle()
                .fill(AppwinCommunityPalette.brand.opacity(0.07))
                .frame(width: 210, height: 210)
            placeholderPost(lines: [96, 72])
                .rotationEffect(.degrees(-7))
                .offset(x: -22, y: -18)
            placeholderPost(lines: [112, 60])
                .rotationEffect(.degrees(5))
                .offset(x: 20, y: 12)
            ZStack {
                Circle()
                    .fill(theme.accentFill)
                Image(systemName: "bubble.left.and.bubble.right.fill")
                    .font(.system(size: 22))
                    .foregroundStyle(.white)
            }
            .frame(width: 56, height: 56)
            .overlay(Circle().strokeBorder(Color.white, lineWidth: 4))
            .shadow(color: AppwinCommunityPalette.brand.opacity(0.3), radius: 12, y: 6)
            .offset(y: 62)
        }
        .frame(width: 220, height: 200)
        .accessibilityHidden(true)
    }

    private func placeholderPost(lines: [CGFloat]) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                Circle()
                    .fill(AppwinCommunityPalette.grey200)
                    .frame(width: 24, height: 24)
                Capsule()
                    .fill(AppwinCommunityPalette.grey200)
                    .frame(width: 56, height: 8)
            }
            ForEach(Array(lines.enumerated()), id: \.offset) { _, width in
                Capsule()
                    .fill(AppwinCommunityPalette.grey100)
                    .frame(width: width, height: 8)
            }
        }
        .padding(14)
        .frame(width: 150, alignment: .leading)
        .background(AppwinCommunityPalette.surface, in: RoundedRectangle(cornerRadius: 16))
        .overlay(
            RoundedRectangle(cornerRadius: 16)
                .strokeBorder(AppwinCommunityPalette.border, lineWidth: 1)
        )
        .shadow(color: Color(communityHex: 0x020617).opacity(0.06), radius: 12, y: 8)
    }
}
