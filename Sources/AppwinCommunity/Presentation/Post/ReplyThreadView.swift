import SwiftUI
import PhotosUI
import UIKit

/// Dedicated replies screen for a root comment (Figma "Réponses").
/// Opened from "→ See N replies" when the thread is collapsed on the post.
struct ReplyThreadView: View {
    @EnvironmentObject private var session: CommunitySession
    @Environment(\.communityTheme) private var theme
    @Environment(\.dismiss) private var dismiss

    let rootCommentId: String
    @ObservedObject var comments: CommentStore
    let onCommentCountChange: (Int) -> Void
    /// When false, do not pop the keyboard on appear (default: open to read).
    var focusComposerOnAppear: Bool = false
    /// When true (push deeplink), scroll to the latest reply once the thread is laid out.
    var scrollToLatestOnAppear: Bool = false

    @State private var draft = ""
    @State private var pendingMedia: [CommunityMedia] = []
    @State private var pickerItem: PhotosPickerItem?
    @State private var isUploading = false
    @State private var selectedProfileId: String?
    @State private var scrollToBottomTick = 0
    @State private var didScrollOnAppear = false
    @FocusState private var isComposerFocused: Bool

    private var maxImages: Int { session.config.limits.maxImagesPerPost }

    private var root: CommunityComment? {
        comments.comments.first { $0.id == rootCommentId }
    }

    var body: some View {
        VStack(spacing: 0) {
            CommunityNavHeader(
                leadingTitle: CommunityStrings.back,
                onLeading: { dismiss() },
                title: CommunityStrings.replies,
                background: theme.colors.surface
            )
            .communityReactionDimmed()

            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 16) {
                        if let root {
                            CommentRow(
                                comment: root,
                                depth: 0,
                                canReact: session.config.features.reactionsEnabled,
                                canReply: session.config.features.repliesEnabled,
                                showTranslation: session.config.features.translationEnabled,
                                availableReactions: session.config.features.reactions,
                                embedReplies: false,
                                onReact: { target, kind in
                                    Task { await comments.toggleReaction(commentId: target.id, kind: kind) }
                                },
                                onReply: { target in
                                    comments.replyingTo = target
                                    isComposerFocused = true
                                },
                                onOpenProfile: session.config.features.profilesEnabled
                                    ? { target in
                                        guard let author = target.author, author.isAddressable else { return }
                                        selectedProfileId = author.id
                                    }
                                    : nil
                            )

                            ForEach(root.replies) { reply in
                                CommentRow(
                                    comment: reply,
                                    depth: 1,
                                    canReact: session.config.features.reactionsEnabled,
                                    canReply: session.config.features.repliesEnabled,
                                    showTranslation: session.config.features.translationEnabled,
                                    availableReactions: session.config.features.reactions,
                                    embedReplies: false,
                                        onReact: { target, kind in
                                        Task { await comments.toggleReaction(commentId: target.id, kind: kind) }
                                    },
                                    onReply: { target in
                                        comments.replyingTo = target
                                        isComposerFocused = true
                                    },
                                    onOpenProfile: session.config.features.profilesEnabled
                                        ? { target in
                                            guard let author = target.author, author.isAddressable else { return }
                                            selectedProfileId = author.id
                                        }
                                        : nil
                                )
                                .id(reply.id)
                                .padding(.leading, 32)
                            }
                        }

                        Color.clear
                            // Extra room so the last reply clears the composer.
                            .frame(height: 24)
                            .id("replies-bottom")
                    }
                    .padding(20)
                }
                .scrollDismissesKeyboard(.interactively)
                .simultaneousGesture(
                    TapGesture().onEnded { dismissComposerKeyboard() }
                )
                .onChange(of: scrollToBottomTick) { _ in
                    withAnimation(.easeOut(duration: 0.25)) {
                        proxy.scrollTo("replies-bottom", anchor: .bottom)
                    }
                }
            }

            if session.config.features.commentsEnabled, session.allows(\.comments), !session.profile.isBanned {
                CommunityCommentBar(
                    draft: $draft,
                    isFocused: $isComposerFocused,
                    placeholder: CommunityStrings.replyToComment,
                    // Replying to the root is the default here: only name someone else.
                    replyingToLabel: comments.replyingTo
                        .flatMap { $0.id == rootCommentId ? nil : $0 }
                        .map { String(format: CommunityStrings.replyingTo, $0.author?.nickname ?? "") },
                    onClearReplyingTo: { comments.replyingTo = root },
                    pendingMedia: $pendingMedia,
                    pickerItem: $pickerItem,
                    isUploading: isUploading,
                    canSend: canSend,
                    onSend: send
                )
                .communityReactionDimmed()
            }
        }
        .background(theme.colors.background.communityReactionDimmed().ignoresSafeArea())
        .communityReactionFocusHost()
        .toolbar(.hidden, for: .navigationBar)
        .communityInteractivePop()
        .alert(CommunityStrings.commentRemovedAlertTitle, isPresented: $comments.showsRemovedNotice) {
            Button(CommunityStrings.understood) {
                Task { await session.bootstrap() }
            }
        } message: {
            Text(CommunityStrings.postRemovedAlertMessage)
        }
        .communityContentActions(CommunityActionHandlers(
            onCommentGone: { comment in
                comments.drop(commentId: comment.id)
                onCommentCountChange(-1)
                if comment.id == rootCommentId { dismiss() }
            }
        ))
        .sheet(item: Binding(
            get: { selectedProfileId.map(ProfileTarget.init) },
            set: { selectedProfileId = $0?.id }
        )) { target in
            ProfileView(profileId: target.id, onCompose: {})
                .environmentObject(session)
        }
        .onAppear {
            if comments.replyingTo == nil, let root {
                comments.replyingTo = root
            }
            if focusComposerOnAppear {
                isComposerFocused = true
            }
            scheduleScrollToLatestIfNeeded()
        }
        .onChange(of: comments.comments.count) { _ in
            scheduleScrollToLatestIfNeeded()
        }
        .onChange(of: pickerItem) { item in
            guard let item else { return }
            Task { await uploadPicked(item) }
        }
    }

    private func scheduleScrollToLatestIfNeeded() {
        guard scrollToLatestOnAppear, !didScrollOnAppear else { return }
        guard root != nil else { return }
        didScrollOnAppear = true
        Task { @MainActor in
            // Wait for LazyVStack to measure the reply rows.
            try? await Task.sleep(nanoseconds: 100_000_000)
            scrollToBottomTick += 1
            try? await Task.sleep(nanoseconds: 150_000_000)
            scrollToBottomTick += 1
        }
    }

    private var canSend: Bool {
        let hasText = !draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        return (hasText || !pendingMedia.isEmpty) && !comments.isSending && !isUploading
    }

    private func dismissComposerKeyboard() {
        isComposerFocused = false
        UIApplication.shared.sendAction(
            #selector(UIResponder.resignFirstResponder),
            to: nil,
            from: nil,
            for: nil
        )
    }

    private func send() {
        let text = draft
        let media = pendingMedia
        // Keep the thread rooted: if the member cleared the banner, still reply
        // to the root rather than posting a top-level comment on the post.
        if comments.replyingTo == nil {
            comments.replyingTo = root
        }
        dismissComposerKeyboard()
        Task {
            let ok = await comments.send(body: text, media: media)
            if ok {
                draft = ""
                pendingMedia = []
                onCommentCountChange(1)
                comments.replyingTo = root
                try? await Task.sleep(nanoseconds: 100_000_000)
                scrollToBottomTick += 1
                try? await Task.sleep(nanoseconds: 150_000_000)
                scrollToBottomTick += 1
            }
        }
    }

    private func uploadPicked(_ item: PhotosPickerItem) async {
        guard pendingMedia.count < maxImages else { return }
        isUploading = true
        defer {
            isUploading = false
            pickerItem = nil
        }
        do {
            guard let data = try await item.loadTransferable(type: Data.self) else { return }
            let media = try await Factory.repository().uploadImage(data, filenamePrefix: "comment")
            pendingMedia.append(media)
        } catch {}
    }
}

/// Navigation value for pushing the replies screen from post detail.
struct ReplyThreadNav: Hashable, Identifiable {
    let id: String
}
