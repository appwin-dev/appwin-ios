import SwiftUI

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

    @StateObject private var comments: CommentStore
    @State private var draft = ""
    @State private var reportTarget: ReportTarget?
    @FocusState private var isComposerFocused: Bool

    init(post: CommunityPost, onCommentCountChange: @escaping (Int) -> Void) {
        self.post = post
        self.onCommentCountChange = onCommentCountChange
        _comments = StateObject(
            wrappedValue: CommentStore(repo: Factory.repository(), postId: post.id)
        )
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: theme.spacing.md) {
                        PostCard(
                            post: post,
                            showTranslation: session.config.features.translationEnabled,
                            canReact: session.config.features.reactionsEnabled,
                            showViews: session.config.features.viewsEnabled,
                            availableReactions: session.config.features.reactions,
                            onTapPost: {},
                            onTapAuthor: {},
                            onReact: { _ in },
                            onComment: { isComposerFocused = true },
                            onMore: {}
                        )

                        Text(CommunityStrings.comments)
                            .font(theme.font(15, weight: .semibold))
                            .foregroundStyle(theme.colors.textPrimary)
                            .padding(.top, theme.spacing.sm)

                        if comments.isLoading && comments.comments.isEmpty {
                            ProgressView().tint(theme.colors.accent)
                                .frame(maxWidth: .infinity)
                                .padding(theme.spacing.lg)
                        } else if comments.comments.isEmpty {
                            CommunityEmptyState(
                                systemImage: "bubble.left",
                                title: CommunityStrings.noComments,
                                message: CommunityStrings.beFirstToComment
                            )
                        } else {
                            ForEach(comments.comments) { comment in
                                CommentRow(
                                    comment: comment,
                                    depth: 0,
                                    canReact: session.config.features.reactionsEnabled,
                                    canReply: session.config.features.repliesEnabled,
                                    showTranslation: session.config.features.translationEnabled,
                                    onLike: {
                                        Task {
                                            await comments.toggleReaction(
                                                commentId: comment.id,
                                                kind: .like
                                            )
                                        }
                                    },
                                    onReply: {
                                        comments.replyingTo = comment
                                        isComposerFocused = true
                                    },
                                    onDelete: {
                                        Task {
                                            await comments.delete(commentId: comment.id)
                                            onCommentCountChange(-1)
                                        }
                                    },
                                    onReport: {
                                        reportTarget = ReportTarget(
                                            type: "comment",
                                            id: comment.id
                                        )
                                    }
                                )
                                .onAppear {
                                    if comment.id == comments.comments.last?.id {
                                        Task { await comments.loadMore() }
                                    }
                                }
                            }
                        }
                    }
                    .padding(theme.spacing.md)
                }

                if session.config.features.commentsEnabled, !session.profile.isBanned {
                    composer
                }
            }
            .background(theme.colors.background)
            .navigationTitle(CommunityStrings.comments)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button(CommunityStrings.close) { dismiss() }
                        .foregroundStyle(theme.colors.accent)
                }
            }
        }
        .sheet(item: $reportTarget) { target in
            ReportSheet(target: target).environmentObject(session)
        }
        .task { await comments.load() }
    }

    private var composer: some View {
        VStack(spacing: 0) {
            Divider().overlay(theme.colors.border)

            if let replyingTo = comments.replyingTo {
                HStack {
                    Text(String(
                        format: CommunityStrings.replyingTo,
                        replyingTo.author?.nickname ?? ""
                    ))
                    .font(theme.font(12))
                    .foregroundStyle(theme.colors.textTertiary)
                    Spacer()
                    Button {
                        comments.replyingTo = nil
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundStyle(theme.colors.textTertiary)
                    }
                    .buttonStyle(.plain)
                }
                .padding(.horizontal, theme.spacing.md)
                .padding(.top, theme.spacing.sm)
            }

            HStack(spacing: theme.spacing.sm) {
                CommunityAvatar(
                    url: session.profile.avatarUrl,
                    nickname: session.profile.nickname,
                    size: 32
                )

                TextField(CommunityStrings.addComment, text: $draft, axis: .vertical)
                    .focused($isComposerFocused)
                    .font(theme.font(14))
                    .lineLimit(1...4)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                    .background(
                        theme.colors.surface,
                        in: RoundedRectangle(cornerRadius: theme.radius.field)
                    )

                Button {
                    send()
                } label: {
                    Image(systemName: "arrow.up.circle.fill")
                        .font(.system(size: 28))
                        .foregroundStyle(canSend ? theme.colors.accent : theme.colors.textTertiary)
                }
                .buttonStyle(.plain)
                .disabled(!canSend)
            }
            .padding(theme.spacing.md)
        }
        .background(theme.colors.background)
    }

    private var canSend: Bool {
        !draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && !comments.isSending
    }

    private func send() {
        let text = draft
        Task {
            let ok = await comments.send(body: text)
            // The field is only cleared on success: losing a comment because the
            // network dropped would be the worst possible outcome.
            if ok {
                draft = ""
                onCommentCountChange(1)
            }
        }
    }
}

/// Comment row, with its replies indented.
struct CommentRow: View {
    let comment: CommunityComment
    let depth: Int
    let canReact: Bool
    let canReply: Bool
    let showTranslation: Bool
    let onLike: () -> Void
    let onReply: () -> Void
    let onDelete: () -> Void
    let onReport: () -> Void

    @Environment(\.communityTheme) private var theme
    @State private var showsActions = false

    private var displayedBody: String {
        showTranslation ? (comment.translatedBody ?? comment.body) : comment.body
    }

    var body: some View {
        VStack(alignment: .leading, spacing: theme.spacing.sm) {
            HStack(alignment: .top, spacing: theme.spacing.sm) {
                CommunityAvatar(
                    url: comment.author?.avatarUrl,
                    nickname: comment.author?.nickname ?? "?",
                    size: 32
                )

                VStack(alignment: .leading, spacing: 4) {
                    HStack(spacing: 6) {
                        Text(comment.author?.nickname ?? "")
                            .font(theme.font(13, weight: .semibold))
                            .foregroundStyle(theme.colors.textPrimary)
                        if comment.author?.isTeam == true {
                            CommunityTeamBadge()
                        }
                        CommunityRelativeDate(date: comment.createdAt)
                    }

                    Text(displayedBody)
                        .font(theme.font(14))
                        .foregroundStyle(theme.colors.textPrimary)
                        .fixedSize(horizontal: false, vertical: true)

                    HStack(spacing: theme.spacing.md) {
                        if canReact {
                            Button(action: onLike) {
                                HStack(spacing: 4) {
                                    Image(systemName: comment.myReaction == nil ? "heart" : "heart.fill")
                                        .font(.system(size: 12))
                                    if comment.likeCount > 0 {
                                        Text("\(comment.likeCount)").font(theme.font(12))
                                    }
                                }
                                .foregroundStyle(
                                    comment.myReaction == nil
                                        ? theme.colors.textTertiary
                                        : theme.colors.accent
                                )
                            }
                            .buttonStyle(.plain)
                        }

                        // A reply cannot itself be replied to: the thread stays
                        // flat, as it is server-side.
                        if canReply, comment.parentCommentId == nil {
                            Button(CommunityStrings.reply, action: onReply)
                                .font(theme.font(12, weight: .medium))
                                .foregroundStyle(theme.colors.textTertiary)
                                .buttonStyle(.plain)
                        }

                        Spacer(minLength: 0)

                        Button {
                            showsActions = true
                        } label: {
                            Image(systemName: "ellipsis")
                                .font(.system(size: 12))
                                .foregroundStyle(theme.colors.textTertiary)
                        }
                        .buttonStyle(.plain)
                    }
                }
            }

            ForEach(comment.replies) { reply in
                CommentRow(
                    comment: reply,
                    depth: depth + 1,
                    canReact: canReact,
                    canReply: canReply,
                    showTranslation: showTranslation,
                    onLike: onLike,
                    onReply: onReply,
                    onDelete: onDelete,
                    onReport: onReport
                )
                .padding(.leading, theme.spacing.xl)
            }

            if comment.hiddenReplyCount > 0 {
                Text(CommunityStrings.showReplies(comment.hiddenReplyCount))
                    .font(theme.font(12, weight: .medium))
                    .foregroundStyle(theme.colors.accent)
                    .padding(.leading, theme.spacing.xl)
            }
        }
        .confirmationDialog("", isPresented: $showsActions) {
            if comment.canDelete {
                Button(CommunityStrings.delete, role: .destructive, action: onDelete)
            } else {
                Button(CommunityStrings.report, action: onReport)
            }
            Button(CommunityStrings.cancel, role: .cancel) {}
        }
    }
}
