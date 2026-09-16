//
//  ConversationsView.swift
//  AppwinSupport
//
//  Page « Mes conversations » - inbox customer.
//  Navigation: custom back plus edge swipe, as in MessengerView.
//

import SwiftUI

struct ConversationsView: View {
  @Environment(\.appwinTheme) private var theme
  @EnvironmentObject private var conversationStore: ConversationStore
  @EnvironmentObject private var router: AppwinRouter

  var body: some View {
    ConversationList(
      store: conversationStore,
      onStartConversation: { router.push(.newConversation) }
    )
    .navigationBarTitleDisplayMode(.inline)
    .navigationBarBackButtonHidden(true)
    .enableInteractivePopGesture()
    .toolbar {
      ToolbarItem(placement: .topBarLeading) {
        Button(action: { router.pop() }) {
          SolarIcon(kind: .altArrowLeft, color: theme.colors.textPrimary, size: 20)
        }
        .accessibilityLabel(SupportStrings.back)
      }
      ToolbarItem(placement: .principal) {
        Text(SupportStrings.conversationsTitle)
          .font(.system(size: 16, weight: .medium))
          .foregroundColor(theme.colors.textPrimary)
          .lineLimit(1)
      }
    }
    .task { await conversationStore.getAll() }
  }
}
