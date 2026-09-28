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
    private var imagesEnabled: Bool { session.config.features.imagesEnabled }

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

    var body: some View {
        VStack(spacing: 0) {
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: theme.spacing.md) {
                        PostCard(
                            post: currentPost,
                            showTranslation: session.config.features.translationEnabled,
                            canReact: session.config.features.reactionsEnabled,
                            showViews: session.config.features.viewsEnabled,
                            availableReactions: session.config.features.reactions,
                            onTapPost: {},
                            onTapAuthor: session.config.features.profilesEnabled
                                ? {
                                    guard let author = currentPost.author, author.isAddressable else { return }
                                    selectedProfileId = author.id
                                }
                                : nil,
                            onReact: { _ in },
                            onComment: { isComposerFocused = true },
                            onMore: { moreActionsPost = currentPost }
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
                                commentTree(comment)
                                    .id(comment.id)
                                    .onAppear {
                                        if comment.id == comments.comments.last?.id {
                                            Task { await comments.loadMore() }
                                        }
                                    }
                            }
                        }

                        Color.clear
                            // Extra room so the last comment clears the composer.
                            .frame(height: 24)
                            .id("comments-bottom")
                    }
                    .padding(theme.spacing.md)
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
                composer
            }
        }
        .background(theme.colors.background)
        .navigationTitle(detailTitle)
        .navigationBarTitleDisplayMode(.inline)
        .navigationBarBackButtonHidden(false)
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

    private var detailTitle: String {
        let nickname = currentPost.author?.nickname.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        if nickname.isEmpty { return CommunityStrings.publications }
        return CommunityStrings.postDetailTitle(nickname)
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

            if !pendingMedia.isEmpty || isUploading {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        ForEach(Array(pendingMedia.enumerated()), id: \.offset) { index, item in
                            ZStack(alignment: .topTrailing) {
                                AsyncImage(url: item.url) { phase in
                                    switch phase {
                                    case .success(let image):
                                        image.resizable().scaledToFill()
                                    default:
                                        theme.colors.border.opacity(0.4)
                                    }
                                }
                                .frame(width: 56, height: 56)
                                .clipShape(RoundedRectangle(cornerRadius: theme.radius.small))

                                Button {
                                    pendingMedia.remove(at: index)
                                } label: {
                                    Image(systemName: "xmark.circle.fill")
                                        .foregroundStyle(.white, .black.opacity(0.55))
                                }
                                .offset(x: 4, y: -4)
                            }
                        }
                        if isUploading {
                            ZStack {
                                theme.colors.border.opacity(0.45)
                                ProgressView()
                                    .tint(theme.colors.accent)
                            }
                            .frame(width: 56, height: 56)
                            .clipShape(RoundedRectangle(cornerRadius: theme.radius.small))
                            .accessibilityLabel(CommunityStrings.addPhoto)
                        }
                    }
                    .padding(.horizontal, theme.spacing.md)
                }
                .padding(.top, theme.spacing.sm)
            }

            HStack(spacing: theme.spacing.sm) {
                if imagesEnabled {
                    PhotosPicker(
                        selection: $pickerItem,
                        matching: .images
                    ) {
                        Image(systemName: "photo")
                            .font(.system(size: 18, weight: .medium))
                            .foregroundStyle(
                                pendingMedia.count >= maxImages || isUploading
                                    ? theme.colors.textTertiary.opacity(0.5)
                                    : theme.colors.textTertiary
                            )
                            .frame(width: 32, height: 32)
                    }
                    .disabled(pendingMedia.count >= maxImages || isUploading)
                    .accessibilityLabel(CommunityStrings.addPhoto)
                }

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
            let uploaded = try await Factory.repository().uploadMedia(
                data: data,
                mimeType: "image/jpeg",
                filename: "comment-\(UUID().uuidString).jpg",
                width: nil,
                height: nil
            )
            pendingMedia.append(
                CommunityMedia(
                    url: uploaded.publicUrl,
                    width: uploaded.width,
                    height: uploaded.height,
                    alt: nil,
                    type: .image
                )
            )
        } catch {
            // Leave pendingMedia unchanged so a failed upload does not wipe
            // images the member already attached.
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
    var availableReactions: [CommunityReactionKind] = CommunityReactionKind.allCases
    /// When false, the parent screen lists replies itself (dedicated thread view).
    var embedReplies: Bool = true
    /// Soft grey bubble around the body, as on the "Réponses" mock.
    var useBubbleStyle: Bool = false
    let onReact: (CommunityComment, CommunityReactionKind) -> Void
    let onReply: (CommunityComment) -> Void
    let onDelete: (CommunityComment) -> Void
    let onReport: (CommunityComment) -> Void
    var onExpandReplies: (() -> Void)? = nil
    var onOpenProfile: ((CommunityComment) -> Void)? = nil

    @Environment(\.communityTheme) private var theme
    @State private var showsActions = false
    @State private var showsReactionPicker = false
    @State private var showsReactionBreakdown = false

    private var displayedBody: String {
        showTranslation ? (comment.translatedBody ?? comment.body) : comment.body
    }

    private var defaultReaction: CommunityReactionKind {
        availableReactions.first ?? .like
    }

    private var pickerReactions: [CommunityReactionKind] {
        availableReactions.count > 1 ? availableReactions : Array(CommunityReactionKind.allCases)
    }

    private var reactionSummaryEmojis: String {
        let kinds: [CommunityReactionKind]
        if !comment.topReactions.isEmpty {
            kinds = Array(comment.topReactions.prefix(3))
        } else if !comment.reactionCounts.isEmpty {
            kinds = comment.reactionCounts.sorted { $0.count > $1.count }.prefix(3).map(\.kind)
        } else {
            kinds = [comment.myReaction].compactMap { $0 }
        }
        let emojis = kinds.map(\.emoji)
        return emojis.isEmpty ? "❤️" : emojis.joined()
    }

    private var shouldCollapseReplies: Bool {
        // One reply stays inline; from the second on, "See N replies".
        embedReplies && depth == 0 && comment.replyCount > 1
    }

    private var showsRepliesInline: Bool {
        embedReplies && !comment.replies.isEmpty && !shouldCollapseReplies
    }

    @ViewBuilder
    private var commentAuthorAvatar: some View {
        let avatar = CommunityAvatar(
            url: comment.author?.avatarUrl,
            nickname: comment.author?.nickname ?? "?",
            size: 32
        )
        if let onOpenProfile, let author = comment.author, author.isAddressable {
            Button { onOpenProfile(comment) } label: { avatar }
                .buttonStyle(.plain)
        } else {
            avatar
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: theme.spacing.sm) {
            HStack(alignment: .top, spacing: theme.spacing.sm) {
                commentAuthorAvatar

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

                    if !displayedBody.isEmpty {
                        Text(displayedBody)
                            .font(theme.font(14))
                            .foregroundStyle(theme.colors.textPrimary)
                            .fixedSize(horizontal: false, vertical: true)
                            .padding(useBubbleStyle ? EdgeInsets(top: 10, leading: 12, bottom: 10, trailing: 12) : EdgeInsets())
                            .frame(
                                maxWidth: useBubbleStyle ? .infinity : nil,
                                alignment: .leading
                            )
                            .background(
                                useBubbleStyle
                                    ? AppwinCommunityPalette.grey100
                                    : Color.clear,
                                in: RoundedRectangle(cornerRadius: useBubbleStyle ? 12 : 0)
                            )
                    }

                    if !comment.media.isEmpty {
                        ScrollView(.horizontal, showsIndicators: false) {
                            HStack(spacing: 6) {
                                ForEach(comment.media) { item in
                                    if item.isVideo {
                                        CommunityVideoThumbnail(media: item)
                                            .frame(width: 120, height: 120)
                                            .clipShape(RoundedRectangle(cornerRadius: theme.radius.small))
                                    } else {
                                        CommunityTappableImage(url: item.url, alt: item.alt)
                                            .frame(width: 120, height: 120)
                                            .clipShape(RoundedRectangle(cornerRadius: theme.radius.small))
                                    }
                                }
                            }
                        }
                        .padding(.top, 2)
                    }

                    HStack(spacing: theme.spacing.md) {
                        if canReact {
                            likeAction
                        }

                        // Reply is allowed on replies too: the API re-parents
                        // under the root so the thread stays one level deep.
                        if canReply {
                            Button { onReply(comment) } label: {
                                HStack(spacing: 4) {
                                    Image(systemName: "bubble.left")
                                        .font(.system(size: 12))
                                    Text(CommunityStrings.reply)
                                        .font(theme.font(12, weight: .medium))
                                }
                                .foregroundStyle(theme.colors.textTertiary)
                            }
                            .buttonStyle(.plain)
                        }

                        Spacer(minLength: 0)

                        if comment.likeCount > 0 {
                            Button {
                                showsReactionBreakdown = true
                            } label: {
                                Text("\(reactionSummaryEmojis) \(comment.likeCount)")
                                    .font(theme.font(12))
                                    .foregroundStyle(theme.colors.textTertiary)
                            }
                            .buttonStyle(.plain)
                        }

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

            if showsRepliesInline {
                ForEach(comment.replies) { reply in
                    CommentRow(
                        comment: reply,
                        depth: depth + 1,
                        canReact: canReact,
                        canReply: canReply,
                        showTranslation: showTranslation,
                        availableReactions: availableReactions,
                        onReact: onReact,
                        onReply: onReply,
                        onDelete: onDelete,
                        onReport: onReport,
                        onOpenProfile: onOpenProfile
                    )
                    .padding(.leading, theme.spacing.xl)
                }
            }

            if shouldCollapseReplies {
                Button {
                    onExpandReplies?()
                } label: {
                    Text(CommunityStrings.showReplies(comment.replyCount))
                        .font(theme.font(13, weight: .medium))
                        .foregroundStyle(theme.colors.accent)
                }
                .buttonStyle(.plain)
                .padding(.leading, 40)
                .padding(.top, 2)
            }
        }
        .confirmationDialog("", isPresented: $showsActions) {
            if comment.canDelete {
                Button(CommunityStrings.delete, role: .destructive) { onDelete(comment) }
            } else {
                Button(CommunityStrings.report) { onReport(comment) }
            }
            Button(CommunityStrings.cancel, role: .cancel) {}
        }
        .sheet(isPresented: $showsReactionBreakdown) {
            ReactionBreakdownSheet(counts: comment.reactionCounts, total: comment.likeCount)
                .presentationDetents([.medium])
                .presentationDragIndicator(.visible)
        }
    }

    private var likeAction: some View {
        Button { onReact(comment, defaultReaction) } label: {
            HStack(spacing: 4) {
                if let mine = comment.myReaction {
                    Text(mine.emoji)
                        .font(.system(size: 12))
                } else {
                    Image(systemName: "heart")
                        .font(.system(size: 12))
                }
                Text(CommunityStrings.like)
                    .font(theme.font(12, weight: .medium))
            }
            .foregroundStyle(
                comment.myReaction == nil
                    ? theme.colors.textTertiary
                    : theme.colors.accent
            )
        }
        .buttonStyle(.plain)
        .simultaneousGesture(
            LongPressGesture(minimumDuration: 0.35)
                .onEnded { _ in
                    withAnimation(.easeOut(duration: 0.15)) {
                        showsReactionPicker = true
                    }
                }
        )
        .overlay(alignment: .topLeading) {
            if showsReactionPicker {
                commentReactionPicker
                    .offset(y: -48)
            }
        }
    }

    private var commentReactionPicker: some View {
        HStack(spacing: 4) {
            ForEach(pickerReactions, id: \.self) { kind in
                Button {
                    onReact(comment, kind)
                    withAnimation(.easeOut(duration: 0.12)) {
                        showsReactionPicker = false
                    }
                } label: {
                    Text(kind.emoji)
                        .font(.system(size: 24))
                        .frame(width: 32, height: 32)
                        .background(
                            kind == comment.myReaction
                                ? theme.colors.border.opacity(0.55)
                                : Color.clear,
                            in: RoundedRectangle(cornerRadius: 8)
                        )
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 6)
        .background(theme.colors.surface, in: Capsule())
        .shadow(color: .black.opacity(0.12), radius: 10, y: 4)
        .onTapGesture {}
        .background(
            Color.clear
                .contentShape(Rectangle())
                .frame(width: 2000, height: 2000)
                .onTapGesture {
                    withAnimation(.easeOut(duration: 0.12)) {
                        showsReactionPicker = false
                    }
                }
        )
    }
}
