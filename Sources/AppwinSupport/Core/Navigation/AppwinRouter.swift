// Clean iOS 16+ navigation: a Router drives the NavigationStack's path.
// Screens do not know their neighbours - they only say "go there" through
// `router.push(...)`. Injected via @EnvironmentObject.

import SwiftUI

/// Every navigable destination of the messenger. One `enum` means one source
/// of truth for routes. `Hashable` because `NavigationStack` identifies stack
/// elements by value.
enum AppwinRoute: Hashable {
    /// Existing conversation, opened from the list.
    case messenger(Conversation)
    /// Conversation not created yet (Intercom model): the screen opens empty
    /// and the first message sent creates it.
    case newConversation
    /// Dedicated page listing all of the customer's conversations.
    case conversations
    /// FAQ article, opened from home.
    case faq(Faq)
}

extension AppwinRoute {
    /// Destination view for each route, centralised here so `HomeView` only
    /// wires `.navigationDestination(for: AppwinRoute.self) { $0.destination }`.
    @MainActor
    @ViewBuilder
    var destination: some View {
      Group{
        switch self {
        case .messenger(let conversation):
            MessengerView(conversation: conversation)
        case .newConversation:
            MessengerView(conversation: nil)
        case .conversations:
            ConversationsView()
        case .faq(let faq):
            FaqDetailView(faq: faq)
        }
      }
        
    }
}

/// Holds the navigation path and publishes it so `NavigationStack(path:)` can
/// bind to it. `@MainActor` because it touches UI state.
@MainActor
final class AppwinRouter: ObservableObject {
    @Published var path = NavigationPath()

    /// Pushes a destination programmatically.
    /// `createConversation()` on fera `router.push(.messenger(conv))`).
    func push(_ route: AppwinRoute) {
        path.append(route)
    }

    /// Pops. The NavigationStack back button does this on its own too.
    func pop() {
        guard !path.isEmpty else { return }
        path.removeLast()
    }

    /// Clears the stack, returning to the root list.
    func popToRoot() {
        path = NavigationPath()
    }
}
