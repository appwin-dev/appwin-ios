//
//  ConversationsView.swift
//  AppwinSupport
//
//  Page « Mes conversations » - inbox customer. Same bar as the thread and the
//  FAQ article (Figma button/icon-native + centred title on bg/page).
//  Navigation: custom back plus edge swipe, as in MessengerView.
//

import SwiftUI

struct ConversationsView: View {
  @Environment(\.appwinTheme) private var theme
  @EnvironmentObject private var conversationStore: ConversationStore
  @EnvironmentObject private var router: AppwinRouter

  var body: some View {
    VStack(spacing: 0) {
      AppwinNavBar(title: SupportStrings.conversationsTitle) { router.pop() }

      ConversationList(
        store: conversationStore,
        onStartConversation: { router.push(.newConversation) }
      )
    }
    .background(theme.colors.page)
    .navigationBarHidden(true)
    .enableInteractivePopGesture()
    .task { await conversationStore.getAll() }
  }
}
