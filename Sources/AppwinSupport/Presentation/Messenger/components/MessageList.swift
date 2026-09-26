//
//  MessageList.swift
//  AppwinSupport
//
//  Message area: the sheet's slate background, 24 gap, day separators.
//  Welcome message at the top of the thread when starting a conversation.
//  Tap hors composer → ferme le clavier.
//

import SwiftUI
import UIKit

struct MessageList: View {
    @ObservedObject var store: MessageStore
    /// Shows the welcome banner on a new conversation or a creation session.
    var showWelcome: Bool = false
    var welcomeMessage: String? = nil
    let onBackgroundTap: () -> Void
    let onEditMessage: (Message) -> Void
    let onDeleteMessage: (Message) -> Void
    let onToggleReaction: (Message, String) -> Void

    @Environment(\.appwinTheme) private var theme
    @EnvironmentObject private var session: AppwinSession
    /// Which bubble shows the reaction / edit chrome; nil = none.
    @State private var reactionPickerMessageId: String? = nil

    private var listItems: [MessageListItem] {
        MessageDayGrouping.items(from: store.messages, language: SupportDisplayLocale.uiLanguage(customerLanguage: nil))
    }

    private var lastCustomerMessageId: String? {
        store.messages.first(where: { $0.authorType == .customer })?.id
    }

    private var welcomeText: String? {
        guard showWelcome,
              let text = welcomeMessage?.trimmingCharacters(in: .whitespacesAndNewlines),
              !text.isEmpty else { return nil }
        return text
    }

    private var bottomAnchorId: String {
        if store.peerIsTyping { return "typing" }
        return store.messages.first?.id ?? "scroll-bottom"
    }

    var body: some View {
        content
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .scrollDismissesKeyboard(.interactively)
            .background(AppwinTokens.surfaceMuted)
    }

    @ViewBuilder
    private var content: some View {
        if store.isLoading && store.messages.isEmpty && welcomeText == nil {
            ProgressView()
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .contentShape(Rectangle())
                .onTapGesture(perform: dismissKeyboard)
        } else if let error = store.errorLoadMessages, store.messages.isEmpty {
            Text(String(format: SupportStrings.errorPrefix, String(describing: error)))
                .font(.system(size: 12, weight: .medium))
                .foregroundColor(theme.colors.textSecondary)
                .padding()
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .contentShape(Rectangle())
                .onTapGesture(perform: dismissKeyboard)
        } else {
            GeometryReader { geo in
                ScrollViewReader { proxy in
                    ScrollView(.vertical, showsIndicators: false) {
                        LazyVStack(spacing: 24) {
                            if store.hasMoreOlder {
                                ProgressView()
                                    .frame(maxWidth: .infinity)
                                    .onAppear {
                                        Task { await store.loadOlderMessages() }
                                    }
                            }

                            if let welcomeText {
                                WelcomeMessageBanner(message: welcomeText)
                                    .id("welcome")
                            }

                            ForEach(listItems) { item in
                                switch item {
                                case .day(_, let label):
                                    daySeparator(label)
                                case .message(let message, let groupMeta):
                                    MessageBubble(
                                        message: message,
                                        showFooter: groupMeta.isLastInGroup,
                                        showAvatar: groupMeta.isLastInGroup,
                                        showReadReceipt: groupMeta.isLastInGroup
                                            && message.id == lastCustomerMessageId,
                                        onEdit: { onEditMessage(message) },
                                        onDelete: { onDeleteMessage(message) },
                                        onToggleReaction: { emoji in
                                            onToggleReaction(message, emoji)
                                        },
                                        showReactionPicker: Binding(
                                            get: { reactionPickerMessageId == message.id },
                                            set: { open in
                                                withAnimation(.spring(response: 0.28, dampingFraction: 0.86)) {
                                                    reactionPickerMessageId = open ? message.id : nil
                                                }
                                            }
                                        )
                                    )
                                    .padding(.top, groupMeta.isGroupedWithPrevious ? -18 : 0)
                                    .id(message.id)                                }
                            }

                            if store.peerIsTyping {
                                TypingIndicatorView()
                                    .id("typing")
                            }

                            Color.clear
                                .frame(height: 1)
                                .id("scroll-bottom")
                        }
                        .padding(.horizontal, 20)
                        .padding(.vertical, 16)
                        .frame(maxWidth: .infinity, minHeight: geo.size.height, alignment: .top)
                        .contentShape(Rectangle())
                        .onTapGesture(perform: dismissKeyboard)
                    }
                    // Dark mode hôte : sans ça le ScrollView garde un fond système sombre
                    // (bande en haut au scroll / après envoi + clavier).
                    .scrollContentBackground(.hidden)
                    .background(AppwinTokens.surfaceMuted)
                    .onAppear {
                        scrollToBottom(proxy, animated: false)
                    }
                    .onChange(of: store.messages.first?.id) { _ in
                        scrollToBottom(proxy, animated: true)
                    }
                    .onChange(of: store.peerIsTyping) { typing in
                        if typing {
                            scrollToBottom(proxy, animated: true)
                        }
                    }
                }
            }
        }
    }

    private func dismissKeyboard() {
        if reactionPickerMessageId != nil {
            withAnimation(.spring(response: 0.28, dampingFraction: 0.86)) {
                reactionPickerMessageId = nil
            }
        }
        onBackgroundTap()
        UIApplication.shared.sendAction(
            #selector(UIResponder.resignFirstResponder),
            to: nil,
            from: nil,
            for: nil
        )
    }

    private func scrollToBottom(_ proxy: ScrollViewProxy, animated: Bool) {
        let target = bottomAnchorId
        let scroll = { proxy.scrollTo(target, anchor: .bottom) }
        if animated {
            withAnimation(.easeOut(duration: 0.2)) { scroll() }
        } else {
            DispatchQueue.main.async { scroll() }
        }
    }

    private func daySeparator(_ label: String) -> some View {
        HStack(spacing: 12) {
            Rectangle()
                .fill(theme.colors.border)
                .frame(height: 1)
            Text(label)
                .font(.system(size: 10, weight: .medium))
                .foregroundColor(theme.colors.textTertiary)
                .fixedSize()
            Rectangle()
                .fill(theme.colors.border)
                .frame(height: 1)
        }
    }
}
