import SwiftUI
import UIKit

/// Figma emoji bar (178:2561): opened by a long press on a post's heart or a
/// comment's bubble, scrolls when the studio offers more than fit.
struct CommunityReactionBar: View {
    let reactions: [CommunityReactionKind]
    let selected: CommunityReactionKind?
    let onPick: (CommunityReactionKind) -> Void

    @Environment(\.communityTheme) private var theme

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 12) {
                ForEach(reactions, id: \.self) { kind in
                    Button { onPick(kind) } label: {
                        Text(kind.emoji)
                            .font(.system(size: 22))
                            .frame(width: 28, height: 28)
                            .background(
                                kind == selected ? theme.colors.raised : .clear,
                                in: RoundedRectangle(cornerRadius: 8)
                            )
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(CommunityStrings.reactionLabel(kind))
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
        }
        .frame(maxWidth: 300)
        .fixedSize(horizontal: false, vertical: true)
        .background(theme.colors.surface, in: Capsule())
        .shadow(color: .black.opacity(0.12), radius: 12, y: 4)
    }
}

/// Figma reaction summary: the three most used emojis, tight, then the count.
struct CommunityReactionSummary: View {
    let top: [CommunityReactionKind]
    var count: Int?

    @Environment(\.communityTheme) private var theme

    var body: some View {
        HStack(spacing: 4) {
            HStack(spacing: 1) {
                ForEach(top.prefix(3), id: \.self) { kind in
                    Text(kind.emoji).font(.system(size: 12))
                }
            }
            if let count {
                Text("\(count)")
                    .font(theme.font(12, weight: .medium))
                    .foregroundStyle(theme.colors.textTertiary)
            }
        }
    }
}

extension View {
    /// Tap, and a long press that fires as soon as it is held (with a haptic),
    /// not on release. Releasing a long press never also counts as a tap.
    func communityPress(onTap: @escaping () -> Void, onLongPress: @escaping () -> Void) -> some View {
        modifier(CommunityPress(onTap: onTap, onLongPress: onLongPress))
    }
}

private struct CommunityPress: ViewModifier {
    let onTap: () -> Void
    let onLongPress: () -> Void

    @State private var longPressFired = false

    func body(content: Content) -> some View {
        content
            .onTapGesture {
                if longPressFired {
                    longPressFired = false
                } else {
                    onTap()
                }
            }
            .simultaneousGesture(
                LongPressGesture(minimumDuration: 0.25, maximumDistance: 12).onEnded { _ in
                    longPressFired = true
                    UIImpactFeedbackGenerator(style: .medium).impactOccurred()
                    onLongPress()
                }
            )
    }
}
