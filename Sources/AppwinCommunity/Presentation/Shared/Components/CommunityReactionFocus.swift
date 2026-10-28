import SwiftUI

/// Which post or comment has its emoji bar open on the screen (Figma 178:2456):
/// that one comes forward, everything else dims and closes the bar on tap.
///
/// Each element dims itself rather than one backdrop covering the screen: a
/// lazy list ignores `zIndex`, so later rows would draw over a shared backdrop.
@MainActor
final class CommunityReactionFocus: ObservableObject {
    @Published var focusedId: String?
}

private struct CommunityReactionFocusKey: EnvironmentKey {
    static let defaultValue: CommunityReactionFocus? = nil
}

extension EnvironmentValues {
    var communityReactionFocus: CommunityReactionFocus? {
        get { self[CommunityReactionFocusKey.self] }
        set { self[CommunityReactionFocusKey.self] = newValue }
    }
}

extension View {
    /// One per screen holding posts or comments.
    func communityReactionFocusHost() -> some View {
        modifier(ReactionFocusHost())
    }

    /// A post or comment that can open its emoji bar: forward while `isActive`,
    /// dimmed while another one is.
    func communityReactionFocusable(id: String, isActive: Binding<Bool>, cornerRadius: CGFloat) -> some View {
        modifier(ReactionFocusable(id: id, isActive: isActive, cornerRadius: cornerRadius))
    }

    /// Anything else on the screen (header, buttons, page): dimmed while a bar is
    /// open. `ownerId` is the post or comment it belongs to (a pinned badge): it
    /// stays bright with its owner.
    func communityReactionDimmed(cornerRadius: CGFloat = 0, ownerId: String? = nil) -> some View {
        modifier(ReactionDimmed(cornerRadius: cornerRadius, ownerId: ownerId))
    }
}

private struct ReactionFocusHost: ViewModifier {
    @StateObject private var focus = CommunityReactionFocus()

    func body(content: Content) -> some View {
        content.environment(\.communityReactionFocus, focus)
    }
}

private struct ReactionFocusable: ViewModifier {
    let id: String
    @Binding var isActive: Bool
    let cornerRadius: CGFloat

    @Environment(\.communityReactionFocus) private var focus

    func body(content: Content) -> some View {
        let lifted = content
            .scaleEffect(isActive ? 1.02 : 1)
            .shadow(color: .black.opacity(isActive ? 0.12 : 0), radius: 16, y: 8)
        if let focus {
            lifted.modifier(FocusSync(id: id, isActive: $isActive, focus: focus, cornerRadius: cornerRadius))
        } else {
            lifted
        }
    }
}

private struct FocusSync: ViewModifier {
    let id: String
    @Binding var isActive: Bool
    @ObservedObject var focus: CommunityReactionFocus
    let cornerRadius: CGFloat

    func body(content: Content) -> some View {
        content
            .overlay { DimLayer(focus: focus, isDimmed: focus.focusedId != nil && focus.focusedId != id, cornerRadius: cornerRadius) }
            .onChange(of: isActive) { active in
                if active {
                    focus.focusedId = id
                } else if focus.focusedId == id {
                    withAnimation(.easeOut(duration: 0.15)) { focus.focusedId = nil }
                }
            }
            .onChange(of: focus.focusedId) { focused in
                if focused != id, isActive {
                    withAnimation(.easeOut(duration: 0.15)) { isActive = false }
                }
            }
    }
}

private struct ReactionDimmed: ViewModifier {
    let cornerRadius: CGFloat
    let ownerId: String?

    @Environment(\.communityReactionFocus) private var focus

    func body(content: Content) -> some View {
        if let focus {
            content.overlay { ObservedDim(focus: focus, cornerRadius: cornerRadius, ownerId: ownerId) }
        } else {
            content
        }
    }
}

private struct ObservedDim: View {
    @ObservedObject var focus: CommunityReactionFocus
    let cornerRadius: CGFloat
    let ownerId: String?

    var body: some View {
        DimLayer(
            focus: focus,
            isDimmed: focus.focusedId != nil && focus.focusedId != ownerId,
            cornerRadius: cornerRadius
        )
    }
}

/// The grey veil; it also swallows the tap, which only closes the bar.
private struct DimLayer: View {
    let focus: CommunityReactionFocus
    let isDimmed: Bool
    let cornerRadius: CGFloat

    var body: some View {
        if isDimmed {
            RoundedRectangle(cornerRadius: cornerRadius)
                .fill(Color.black.opacity(0.18))
                .contentShape(Rectangle())
                .onTapGesture {
                    withAnimation(.easeOut(duration: 0.15)) { focus.focusedId = nil }
                }
                .transition(.opacity)
        }
    }
}
