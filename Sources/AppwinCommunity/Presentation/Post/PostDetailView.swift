import SwiftUI
import PhotosUI
import UIKit

/// Post detail: the post at the top, its comment thread, and the input field
/// anchored at the bottom.
struct PostDetailView: View {
    @EnvironmentObject private var session: CommunitySession
    @Environment(\.communityTheme) private var theme
    @Environment(\.dismiss) private var dismiss

    let post: CommunityPost
    /// Reports the change in comment count so the feed keeps its counter current
    /// without a refetch.
    let onCommentCountChange: (Int) -> Void
    /// Called after a successful delete so the feed can drop the card.
    var onDeleted: (() -> Void)? = nil
    /// Called after a successful edit so the feed can refresh the card.
    var onUpdated: ((CommunityPost) -> Void)? = nil
    /// Opens the dedicated "Réponses" screen via the parent NavigationStack.
    var onOpenThread: ((String) -> Void)? = nil

    @StateObject private var comments: CommentStore
    @State private var currentPost: CommunityPost
    @State private var draft = ""
    @State private var reportTarget: ReportTarget?
    @State private var moreActionsPost: CommunityPost?
    @State private var editingPost: CommunityPost?
    @State private var pendingDeletion = false
    @State private var pendingMedia: [CommunityMedia] = []
    @State private var pickerItem: PhotosPickerItem?
    @State private var isUploading = false
    @State private var selectedProfileId: String?
    /// Bumped after a successful send so the list scrolls to the new comment.
    @State private var scrollToBottomTick = 0
    @FocusState private var isComposerFocused: Bool

    private var maxImages: Int { session.config.limits.maxImagesPerPost }

    init(
        post: CommunityPost,
        onCommentCountChange: @escaping (Int) -> Void,
        onDeleted: (() -> Void)? = nil,
        onUpdated: ((CommunityPost) -> Void)? = nil,
        onOpenThread: ((String) -> Void)? = nil
    ) {
        self.post = post
        self.onCommentCountChange = onCommentCountChange
        self.onDeleted = onDeleted
        self.onUpdated = onUpdated
        self.onOpenThread = onOpenThread
        _currentPost = State(initialValue: post)
        _comments = StateObject(
            wrappedValue: CommentStore(repo: Factory.repository(), postId: post.id)
        )
    }

    /// Figma commentary (19:5233): white bar, the post full-bleed, the
    /// comments on bg/page, the comment bar pinned at the bottom.
    var body: some View {
        VStack(spacing: 0) {
            CommunityNavHeader(
                leadingTitle: CommunityStrings.back,
                onLeading: { dismiss() },
                title: CommunityStrings.comment,
                background: theme.colors.surface
            )

            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 0) {
                        PostCard(
                            post: currentPost,
                            showTranslation: session.config.features.translationEnabled,
                            canReact: session.config.features.reactionsEnabled,
                            showViews: session.config.features.viewsEnabled,
                            availableReactions: session.config.features.reactions,
                            style: .flat,
                            onTapPost: {},
                            onTapAuthor: session.config.features.profilesEnabled
                                ? {
                                    guard let author = currentPost.author, author.isAddressable else { return }
                                    selectedProfileId = author.id
                                }
                                : nil,
                            onReact: { kind in
                                Task { await togglePostReaction(kind) }
                            },
                            onComment: { isComposerFocused = true },
                            onMore: { moreActionsPost = currentPost }
                        )

                        commentsSection
                            .padding(20)

                        Color.clear
                            // Extra room so the last comment clears the comment bar.
                            .frame(height: 24)
                            .id("comments-bottom")
                    }
                }
                .scrollDismissesKeyboard(.interactively)
                .simultaneousGesture(
                    TapGesture().onEnded { dismissComposerKeyboard() }
                )
                .onChange(of: scrollToBottomTick) { _ in
                    withAnimation(.easeOut(duration: 0.25)) {
                        proxy.scrollTo("comments-bottom", anchor: .bottom)
                    }
                }
            }

            if session.config.features.commentsEnabled, !session.profile.isBanned {
                CommunityCommentBar(
                    draft: $draft,
                    isFocused: $isComposerFocused,
                    placeholder: CommunityStrings.addComment,
                    replyingToLabel: comments.replyingTo.map {
                        String(format: CommunityStrings.replyingTo, $0.author?.nickname ?? "")
                    },
                    onClearReplyingTo: { comments.replyingTo = nil },
                    pendingMedia: $pendingMedia,
                    pickerItem: $pickerItem,
                    isUploading: isUploading,
                    canSend: canSend,
                    onSend: send
                )
            }
        }
        .background(theme.colors.background)
        .toolbar(.hidden, for: .navigationBar)
        .communityInteractivePop()
        .onAppear { OpenPost.postId = post.id }
        .onDisappear {
            if OpenPost.postId == post.id { OpenPost.postId = nil }
        }
        .sheet(item: $reportTarget) { target in
            ReportSheet(target: target).environmentObject(session)
        }
        .sheet(item: Binding(
            get: { selectedProfileId.map(ProfileTarget.init) },
            set: { selectedProfileId = $0?.id }
        )) { target in
            ProfileView(profileId: target.id, onCompose: {})
                .environmentObject(session)
        }
        .sheet(item: $editingPost) { target in
            ComposerView(editingPost: target) { updated in
                currentPost = updated
                onUpdated?(updated)
            }
            .environmentObject(session)
        }
        .confirmationDialog("", isPresented: Binding(
            get: { moreActionsPost != nil },
            set: { if !$0 { moreActionsPost = nil } }
        )) {
            if let target = moreActionsPost {
                if target.canEdit {
                    Button(CommunityStrings.edit) {
                        editingPost = target
                    }
                }
                if target.canDelete {
                    Button(CommunityStrings.delete, role: .destructive) {
                        pendingDeletion = true
                    }
                }
                if session.config.features.reportingEnabled, !target.canEdit {
                    Button(CommunityStrings.report) {
                        reportTarget = ReportTarget(type: "post", id: target.id)
                    }
                }
                Button(CommunityStrings.cancel, role: .cancel) {}
            }
        }
        .confirmationDialog(
            CommunityStrings.deletePostTitle,
            isPresented: $pendingDeletion,
            titleVisibility: .visible
        ) {
            Button(CommunityStrings.delete, role: .destructive) {
                Task {
                    try? await Factory.repository().deletePost(postId: post.id)
                    onDeleted?()
                    dismiss()
                }
            }
            Button(CommunityStrings.cancel, role: .cancel) {}
        } message: {
            Text(CommunityStrings.deletePostMessage)
        }
        .task {
            await comments.load()
            // Detail open counts as a view even if the feed debounce never flushed.
            try? await Factory.repository().trackViews(postIds: [post.id])
        }
        .onChange(of: pickerItem) { item in
            guard let item else { return }
            Task { await uploadPicked(item) }
        }
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

    /// Optimistic toggle so the detail card matches the feed without waiting
    /// for the round trip (and so a picker pick is not a silent no-op).
    private func togglePostReaction(_ kind: CommunityReactionKind) async {
        let previous = currentPost
        let optimistic = optimisticReactionState(
            myReaction: previous.myReaction,
            reactionCounts: previous.reactionCounts,
            likeCount: previous.likeCount,
            kind: kind
        )
        currentPost = previous.applying(
            myReaction: optimistic.myReaction,
            topReactions: optimistic.topReactions,
            reactionCounts: optimistic.reactionCounts,
            likeCount: optimistic.likeCount
        )
        onUpdated?(currentPost)

        do {
            let result = try await Factory.repository().reactToPost(
                postId: previous.id,
                kind: kind
            )
            currentPost = currentPost.applying(
                myReaction: result.myReaction.flatMap(CommunityReactionKind.init(rawValue:)),
                topReactions: (result.topReactions ?? []).compactMap(CommunityReactionKind.init(rawValue:)),
                reactionCounts: (result.reactionCounts ?? []).compactMap { $0.toDomain() },
                likeCount: result.likeCount
            )
            onUpdated?(currentPost)
        } catch {
            currentPost = previous
            onUpdated?(previous)
        }
    }

    @ViewBuilder
    private func commentTree(_ comment: CommunityComment) -> some View {
        CommentRow(
            comment: comment,
            depth: 0,
            canReact: session.config.features.reactionsEnabled,
            canReply: session.config.features.repliesEnabled,
            showTranslation: session.config.features.translationEnabled,
            availableReactions: session.config.features.reactions,
            onReact: { target, kind in
                Task { await comments.toggleReaction(commentId: target.id, kind: kind) }
            },
            onReply: { target in
                let rootId = target.parentCommentId ?? target.id
                comments.replyingTo = target
                // Long threads open the dedicated replies screen so the member
                // keeps context instead of typing against a collapsed list.
                if let root = comments.comments.first(where: { $0.id == rootId }),
                   root.replyCount > 1 {
                    onOpenThread?(rootId)
                } else {
                    isComposerFocused = true
                }
            },
            onDelete: { target in
                Task {
                    await comments.delete(commentId: target.id)
                    onCommentCountChange(-1)
                }
            },
            onReport: { target in
                reportTarget = ReportTarget(type: "comment", id: target.id)
            },
            onExpandReplies: { onOpenThread?(comment.id) },
            onOpenProfile: session.config.features.profilesEnabled
                ? { target in
                    guard let author = target.author, author.isAddressable else { return }
                    selectedProfileId = author.id
                }
                : nil
        )
    }

    @ViewBuilder
    private var commentsSection: some View {
        if comments.isLoading && comments.comments.isEmpty {
            ProgressView().tint(theme.colors.accent)
                .frame(maxWidth: .infinity)
                .padding(theme.spacing.lg)
        } else if comments.comments.isEmpty {
            // Figma commentary-empty (29:5471).
            CommunityEmptyState(
                icon: .chatLineDuotone,
                title: CommunityStrings.noComments,
                message: CommunityStrings.beFirstToComment
            )
            .padding(.top, 60)
        } else {
            VStack(alignment: .leading, spacing: 16) {
                Text(CommunityStrings.comments)
                    .font(theme.font(14, weight: .medium))
                    .foregroundStyle(theme.colors.textTertiary)

                ForEach(comments.comments) { comment in
                    commentTree(comment)
                        .id(comment.id)
                        .onAppear {
                            if comment.id == comments.comments.last?.id {
                                Task { await comments.loadMore() }
                            }
                        }
                }
            }
        }
    }

    private var canSend: Bool {
        let hasText = !draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        return (hasText || !pendingMedia.isEmpty) && !comments.isSending && !isUploading
    }

    private func send() {
        let text = draft
        let media = pendingMedia
        let threadRootId = comments.replyingTo.map { $0.parentCommentId ?? $0.id }
        dismissComposerKeyboard()
        Task {
            let ok = await comments.send(body: text, media: media)
            if ok {
                draft = ""
                pendingMedia = []
                onCommentCountChange(1)
                // After a reply on a thread with 2+ replies, open "Réponses"
                // so the new message is visible (inline list stays collapsed).
                if let threadRootId,
                   let root = comments.comments.first(where: { $0.id == threadRootId }),
                   root.replyCount > 1 {
                    onOpenThread?(threadRootId)
                } else {
                    // Let LazyVStack lay out the new row before scrolling.
                    try? await Task.sleep(nanoseconds: 100_000_000)
                    scrollToBottomTick += 1
                    // Second pass after keyboard / safe-area settle.
                    try? await Task.sleep(nanoseconds: 150_000_000)
                    scrollToBottomTick += 1
                }
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
        } catch {
            // Leave pendingMedia unchanged so a failed upload does not wipe
            // images the member already attached.
        }
    }
}
