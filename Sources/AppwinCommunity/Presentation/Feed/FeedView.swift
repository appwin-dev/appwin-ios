import SwiftUI

/// Main screen: group bar, feed, compose button.
///
/// Designed to live full screen in a host app tab, hence no close button by
/// default - `AppwinCommunity.presentCommunity()` adds one when the screen is
/// presented instead.
/// en modal.
struct FeedView: View {
    @EnvironmentObject private var session: CommunitySession
    @EnvironmentObject private var feed: FeedStore
    @Environment(\.communityTheme) private var theme

    let showsCloseButton: Bool
    var onClose: (() -> Void)?

    @State private var composerPresented = false
    @State private var selectedPost: CommunityPost?
    @State private var selectedProfileId: String?
    @State private var moreActionsPost: CommunityPost?
    @State private var reportTarget: ReportTarget?
    @State private var pendingDeletion: CommunityPost?

    var body: some View {
        ZStack(alignment: .bottomTrailing) {
            // The page colour runs edge to edge, under the status bar: the feed
            // is a full-screen tab of the host app, not a sheet floating on a
            // grey mat. Only the content below is inset by the safe area.
            theme.colors.background.ignoresSafeArea()

            VStack(spacing: 0) {
                screenHeader
                content
            }

            if session.canPost {
                composerButton
            }
        }
        .sheet(isPresented: $composerPresented) {
            ComposerView { post in
                feed.prepend(post)
            }
            .environmentObject(session)
        }
        .sheet(item: $selectedPost) { post in
            PostDetailView(post: post) { delta in
                feed.bumpCommentCount(postId: post.id, by: delta)
            }
            .environmentObject(session)
        }
        .sheet(item: Binding(
            get: { selectedProfileId.map(ProfileTarget.init) },
            set: { selectedProfileId = $0?.id }
        )) { target in
            ProfileView(profileId: target.id)
                .environmentObject(session)
        }
        .sheet(item: $reportTarget) { target in
            ReportSheet(target: target)
                .environmentObject(session)
        }
        .confirmationDialog(
            CommunityStrings.deletePostTitle,
            isPresented: Binding(
                get: { pendingDeletion != nil },
                set: { if !$0 { pendingDeletion = nil } }
            ),
            titleVisibility: .visible
        ) {
            Button(CommunityStrings.delete, role: .destructive) {
                if let post = pendingDeletion { deletePost(post) }
            }
            Button(CommunityStrings.cancel, role: .cancel) {}
        } message: {
            Text(CommunityStrings.deletePostMessage)
        }
        .confirmationDialog("", isPresented: Binding(
            get: { moreActionsPost != nil },
            set: { if !$0 { moreActionsPost = nil } }
        )) {
            if let post = moreActionsPost {
                if post.canDelete {
                    Button(CommunityStrings.delete, role: .destructive) {
                        pendingDeletion = post
                    }
                }
                if session.config.features.reportingEnabled, !(post.canEdit) {
                    Button(CommunityStrings.report) {
                        reportTarget = ReportTarget(type: "post", id: post.id)
                    }
                }
                Button(CommunityStrings.cancel, role: .cancel) {}
            }
        }
        .task {
            await feed.load(groupId: session.selectedGroupId)
        }
        // The feed reloads on every tab change: a member switching group
        // expects that group's content, not a mixture.
        //
        // Single-parameter signature: the two-parameter one is iOS 17 only, and
        // the SDK targets iOS 16.
        .onChange(of: session.selectedGroupId) { newValue in
            Task { await feed.load(groupId: newValue) }
        }
        .onDisappear {
            Task { await feed.flushViews() }
        }
    }

    /// Screen header - Figma `screen-header` (2120:24338).
    ///
    /// Replaces the navigation bar: the mock puts a large bold title flush with
    /// the feed, not a centred inline nav title. The mock's bell and expand
    /// glyphs stand for actions the SDK does not have; the slot carries the two
    /// it does - close, when presented modally, and the member's own profile.
    private var screenHeader: some View {
        HStack(spacing: 16) {
            // Hiding the title drops the text alone: the row still carries the
            // feed's actions, and taking those away with it would leave the
            // member no way out of a modally presented screen.
            if session.config.theme.headerTitleVisible {
                Text(headerTitle)
                    .font(theme.font(24, weight: .bold))
                    .foregroundStyle(theme.colors.textPrimary)
                    .lineLimit(1)
                    .frame(maxWidth: .infinity, alignment: .leading)
            } else {
                Spacer(minLength: 0)
            }

            if showsCloseButton {
                Button { onClose?() } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 17, weight: .semibold))
                        .foregroundStyle(theme.colors.textPrimary)
                        .frame(width: 20, height: 20)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel(CommunityStrings.close)
            }

            Button {
                selectedProfileId = session.profile.id
            } label: {
                CommunityAvatar(
                    url: session.profile.avatarUrl,
                    nickname: session.profile.nickname,
                    size: 28
                )
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 16)
        .padding(.top, 12)
        .padding(.bottom, 16)
        .overlay(alignment: .bottom) {
            Rectangle()
                .fill(theme.colors.border)
                .frame(height: 1)
        }
    }

    private var headerTitle: String {
        if let custom = session.config.theme.headerTitle?.trimmingCharacters(in: .whitespaces),
           !custom.isEmpty {
            return custom
        }
        let project = session.config.context.projectName
        return project.isEmpty ? CommunityStrings.title : project
    }

    // MARK: - Contenu

    @ViewBuilder
    private var content: some View {
        if !session.config.features.enabled {
            CommunityEmptyState(
                systemImage: "hourglass",
                title: CommunityStrings.disabledTitle,
                message: CommunityStrings.disabledMessage
            )
        } else if !session.isReady && feed.posts.isEmpty {
            ProgressView().tint(theme.colors.accent)
        } else {
            VStack(spacing: 0) {
                if session.groups.count > 1 {
                    GroupTabBar()
                }
                feedList
            }
        }
    }

    private var feedList: some View {
        ScrollView {
            LazyVStack(spacing: 12) {
                if session.profile.isBanned {
                    bannedNotice
                }

                if feed.posts.isEmpty && !feed.isLoading {
                    CommunityEmptyState(
                        systemImage: "bubble.left.and.bubble.right",
                        title: feed.errorMessage == nil
                            ? CommunityStrings.emptyFeedTitle
                            : CommunityStrings.loadErrorTitle,
                        message: feed.errorMessage == nil
                            ? CommunityStrings.emptyFeedMessage
                            : CommunityStrings.loadErrorMessage,
                        actionTitle: feed.errorMessage == nil ? nil : CommunityStrings.retry,
                        action: feed.errorMessage == nil
                            ? nil
                            : { Task { await feed.load(groupId: session.selectedGroupId) } }
                    )
                    .padding(.top, theme.spacing.xxl)
                }

                ForEach(feed.posts) { post in
                    PostCard(
                        post: post,
                        showTranslation: session.config.features.translationEnabled,
                        canReact: session.config.features.reactionsEnabled,
                        showViews: session.config.features.viewsEnabled,
                        onTapPost: { selectedPost = post },
                        onTapAuthor: {
                            guard session.config.features.profilesEnabled,
                                  let authorId = post.author?.id else { return }
                            selectedProfileId = authorId
                        },
                        onLike: { Task { await feed.toggleReaction(postId: post.id, kind: .like) } },
                        onComment: { selectedPost = post },
                        onMore: { moreActionsPost = post }
                    )
                    .onAppear {
                        feed.markVisible(postId: post.id)
                        // Preload one page ahead, so the user never sees the
                        // bottom of the list.
                        if post.id == feed.posts.last?.id {
                            Task { await feed.loadMore() }
                        }
                    }
                }

                if feed.isLoadingMore {
                    ProgressView()
                        .tint(theme.colors.accent)
                        .padding(theme.spacing.lg)
                }
            }
            .padding(.horizontal, 16)
            .padding(.top, 12)
            // Bottom margin: the floating button must not hide the last post.
            .padding(.bottom, session.canPost ? 96 : 24)
        }
        .refreshable {
            await feed.refresh()
            await session.refreshConfig()
        }
    }

    private var bannedNotice: some View {
        Text(CommunityStrings.bannedNotice)
            .font(theme.font(13))
            .foregroundStyle(theme.colors.textSecondary)
            .padding(theme.spacing.md)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                theme.colors.danger.opacity(0.10),
                in: RoundedRectangle(cornerRadius: theme.radius.small)
            )
    }

    /// Floating compose button - Figma `floating-compose-button` (2120:24440).
    private var composerButton: some View {
        Button { composerPresented = true } label: {
            HStack(spacing: 8) {
                Image(systemName: "square.and.pencil")
                    .font(.system(size: 16, weight: .medium))
                Text(CommunityStrings.newPost)
                    .font(theme.font(17, weight: .semibold))
            }
            .foregroundStyle(theme.colors.onAccent)
            .padding(.horizontal, 20)
            .padding(.vertical, 14)
            .background(theme.composeFill, in: Capsule())
        }
        .buttonStyle(.plain)
        .shadow(color: theme.accentShadow, radius: 8, y: 8)
        .padding(.horizontal, 22)
        .padding(.bottom, 16)
    }

    private func deletePost(_ post: CommunityPost) {
        Task {
            // Optimistic: the post disappears at once. On failure the next
            // refresh brings it back, which is less confusing than a post that
            // stays after tapping Delete.
            feed.remove(postId: post.id)
            try? await Factory.repository().deletePost(postId: post.id)
        }
    }
}

/// Group tab bar, in the "For you / About" style.
struct GroupTabBar: View {
    @EnvironmentObject private var session: CommunitySession
    @Environment(\.communityTheme) private var theme

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: theme.spacing.sm) {
                tab(title: CommunityStrings.allGroups, isActive: session.selectedGroupId == nil) {
                    session.setSelectedGroup(nil)
                }
                ForEach(session.groups) { group in
                    tab(
                        title: [group.emoji, group.name].compactMap { $0 }.joined(separator: " "),
                        isActive: session.selectedGroupId == group.id
                    ) {
                        session.setSelectedGroup(group.id)
                    }
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
        }
        .background(theme.colors.background)
    }

    /// Figma `filter-pills-row` (2120:24351): the active pill is filled with the
    /// accent, the others are surface with a hairline border.
    private func tab(
        title: String,
        isActive: Bool,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            Text(title)
                .font(theme.font(14, weight: isActive ? .semibold : .medium))
                .foregroundStyle(isActive ? theme.colors.onAccent : theme.colors.textPrimary)
                .padding(.horizontal, isActive ? 16 : 12)
                .padding(.vertical, 8)
                .background {
                    if isActive {
                        Capsule().fill(theme.accentFill)
                    } else {
                        Capsule()
                            .fill(theme.colors.surface)
                            .overlay(Capsule().strokeBorder(theme.colors.border, lineWidth: 1))
                    }
                }
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Cibles de feuilles

/// `Identifiable` wrapper, to drive a `sheet(item:)` from a bare id.
struct ProfileTarget: Identifiable {
    let id: String
}

struct ReportTarget: Identifiable {
    let type: String
    let targetId: String

    var id: String { "\(type):\(targetId)" }

    init(type: String, id: String) {
        self.type = type
        self.targetId = id
    }
}
