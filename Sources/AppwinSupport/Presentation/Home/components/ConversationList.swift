//
//  ConversationList.swift
//  AppwinSupport
//
//  Liste « Mes conversations » - cartes, empty state, CTA, pagination.
//

import SwiftUI

struct ConversationList: View {
    @ObservedObject var store: ConversationStore
    @Environment(\.appwinTheme) private var theme
    var onStartConversation: (() -> Void)? = nil

    private let screenBg = Color(hex: 0xF1F5F9)

    var body: some View {
        ScrollView {
            LazyVStack(spacing: 12) {
                if let onStartConversation {
                    Button(action: onStartConversation) {
                        HStack(spacing: 10) {
                            SolarIcon(kind: .pen, color: theme.colors.onAccent, size: 18)
                            Text("Nouvelle conversation")
                                .font(.system(size: 14, weight: .medium))
                                .foregroundColor(theme.colors.onAccent)
                            Spacer(minLength: 0)
                        }
                        .padding(.horizontal, 16)
                        .frame(maxWidth: .infinity, minHeight: 52, maxHeight: 52, alignment: .leading)
                        .background {
                            RoundedRectangle(cornerRadius: theme.radius.card, style: .continuous)
                                .fill(theme.accentFill(autoGradient: theme.design.autoGradient))
                                .overlay(
                                    RoundedRectangle(cornerRadius: theme.radius.card, style: .continuous)
                                        .strokeBorder(Color.white.opacity(0.2), lineWidth: 1.5)
                                )
                        }
                    }
                    .buttonStyle(.plain)
                    .padding(.bottom, 4)
                }

                if store.isLoading && store.conversations.isEmpty {
                    ForEach(0..<4, id: \.self) { _ in
                        skeletonRow
                    }
                } else if let error = store.error, store.conversations.isEmpty {
                    errorState(error)
                } else if store.conversations.isEmpty {
                    emptyState
                } else {
                    ForEach(store.conversations) { conversation in
                        NavigationLink(value: AppwinRoute.messenger(conversation)) {
                            ConversationRow(conversation: conversation)
                        }
                        .buttonStyle(.plain)
                        .onAppear {
                            guard conversation.id == store.conversations.last?.id,
                                  store.hasMore else { return }
                            Task { await store.loadMore() }
                        }
                    }

                    if store.isLoadingMore {
                        ProgressView()
                            .padding(.vertical, 12)
                    }
                }
            }
            .padding(20)
        }
        .background(screenBg)
        .refreshable {
            await store.getAll()
        }
    }

    private var skeletonRow: some View {
        HStack(spacing: 12) {
            Circle()
                .fill(AppwinTokens.surfaceMuted)
                .frame(width: 44, height: 44)
            VStack(alignment: .leading, spacing: 8) {
                RoundedRectangle(cornerRadius: 4)
                    .fill(AppwinTokens.surfaceMuted)
                    .frame(height: 12)
                    .frame(maxWidth: 140)
                RoundedRectangle(cornerRadius: 4)
                    .fill(AppwinTokens.surfaceMuted)
                    .frame(height: 10)
                    .frame(maxWidth: .infinity)
            }
            Spacer(minLength: 0)
        }
        .padding(14)
        .background(Color.white)
        .clipShape(RoundedRectangle(cornerRadius: theme.radius.card, style: .continuous))
        .redacted(reason: .placeholder)
    }

    private var emptyState: some View {
        VStack(spacing: 16) {
            ZStack {
                Circle()
                    .fill(Color.white)
                    .frame(width: 72, height: 72)
                SolarIcon(kind: .inbox, color: AppwinTokens.textLow, size: 32)
            }
            .shadow(color: AppwinTokens.shadowSmooth, radius: 4, y: 2)

            VStack(spacing: 6) {
                Text("Aucune conversation")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundColor(AppwinTokens.textHigh)
                Text("Écris au support pour démarrer - on te répond ici.")
                    .font(.system(size: 13, weight: .medium))
                    .foregroundColor(AppwinTokens.textMedium)
                    .multilineTextAlignment(.center)
            }

            if let onStartConversation {
                Button(action: onStartConversation) {
                    Text("Écrire un message")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundColor(theme.colors.onAccent)
                        .padding(.horizontal, 20)
                        .padding(.vertical, 12)
                        .background(
                            Capsule().fill(theme.accentFill(autoGradient: theme.design.autoGradient))
                        )
                }
                .buttonStyle(.plain)
                .padding(.top, 4)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 48)
        .padding(.horizontal, 24)
    }

    private func errorState(_ error: Error) -> some View {
        VStack(spacing: 12) {
            Text("Impossible de charger")
                .font(.system(size: 15, weight: .semibold))
                .foregroundColor(AppwinTokens.textHigh)
            Text(error.appwinUserMessage)
                .font(.system(size: 13, weight: .medium))
                .foregroundColor(AppwinTokens.textMedium)
                .multilineTextAlignment(.center)
            Button("Réessayer") {
                Task { await store.getAll() }
            }
            .font(.system(size: 14, weight: .semibold))
            .foregroundColor(theme.colors.accent)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 40)
        .padding(.horizontal, 20)
    }
}
