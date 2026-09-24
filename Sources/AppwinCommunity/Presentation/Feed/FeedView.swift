import SwiftUI
import AppwinCore

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
    @State private var editingPost: CommunityPost?
    @State private var path = NavigationPath()
    @State private var openedPost: CommunityPost?
    @State private var selectedProfileId: String?
    @State private var moreActionsPost: CommunityPost?
    @State private var reportTarget: ReportTarget?
    @State private var pendingDeletion: CommunityPost?
    /// Post id from a push tap, kept until the feed page that contains it loads.
    @State private var pendingDeeplink: CommunityPushTarget?

    var body: some View {
        // Push into the post (back chevron), same as Android's route stack -
        // not a sheet that slides up over the feed.
        NavigationStack(path: $path) {
            ZStack(alignment: .bottomTrailing) {
                // The page colour runs edge to edge, under the status bar: the feed
                // is a full-screen tab of the host app, not a sheet floating on a
                // grey mat. Only the content below is inset by the safe area.
                theme.colors.background.ignoresSafeArea()

                // Pin to the top: a plain VStack inside a ZStack is centred by
                // default, which shrinks error / loading states into a mid-screen
                // island with a large empty band above.
                VStack(spacing: 0) {
                    screenHeader
                    content
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)

                if session.canPost {
                    composerButton
                }
            }
            .toolbar(.hidden, for: .navigationBar)
            .navigationDestination(for: PostNavRoute.self) { route in
                if let post = resolvedPost(id: route.id) {
                    PostDetailView(
                        post: post,
                        onCommentCountChange: { delta in
                            feed.bumpCommentCount(postId: post.id, by: delta)
                        },
                        onDeleted: { feed.remove(postId: post.id) },
                        onUpdated: { feed.replace($0) },
                        onOpenThread: { threadId in
                            path.append(
                                ReplyThreadRoute(postId: post.id, rootCommentId: threadId)
                            )
                        }
                    )
                    .environmentObject(session)
                }
            }
            .navigationDestination(for: ReplyThreadRoute.self) { route in
                ReplyThreadDeepLinkHost(
                    postId: route.postId,
                    rootCommentId: route.rootCommentId,
                    fromPushDeeplink: route.fromPushDeeplink
                )
                .environmentObject(session)
            }
        }
        .sheet(isPresented: $composerPresented) {
            ComposerView { post in
                feed.prepend(post)
            }
            .environmentObject(session)
        }
        .sheet(item: $editingPost) { post in
            ComposerView(editingPost: post) { updated in
                feed.replace(updated)
            }
            .environmentObject(session)
        }
        .sheet(item: Binding(
            get: { selectedProfileId.map(ProfileTarget.init) },
            set: { selectedProfileId = $0?.id }
        )) { target in
            ProfileView(profileId: target.id, onCompose: { composerPresented = true })
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
                if post.canEdit {
                    Button(CommunityStrings.edit) {
                        editingPost = post
                    }
                }
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
            await consumePendingDeeplinkIfPossible()
        }
        // The feed reloads on every tab change: a member switching group
        // expects that group's content, not a mixture.
        //
        // Single-parameter signature: the two-parameter one is iOS 17 only, and
        // the SDK targets iOS 16.
        .onChange(of: session.selectedGroupId) { newValue in
            Task {
                await feed.load(groupId: newValue)
                await consumePendingDeeplinkIfPossible()
            }
        }
        .onAppear {
            AppwinPush.register(.community, handler: CommunityPushHandler { target in
                pendingDeeplink = target
                Task { await openPostFromDeeplink(target) }
            })
        }
        .onDisappear {
            AppwinPush.unregister(.community)
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
        // Defaults ship with `enabled: false`. Until bootstrap answers, that
        // must read as loading (or a real error), never "Coming soon" - otherwise
        // a failed bootstrap (wrong base URL, offline API) looks like the studio
        // turned the product off.
        if !session.isReady {
            if session.loadError != nil {
                CommunityEmptyState(
                    systemImage: "exclamationmark.triangle",
                    title: CommunityStrings.loadErrorTitle,
                    message: CommunityStrings.loadErrorMessage,
                    actionTitle: CommunityStrings.retry,
                    expandsToFill: true,
                    action: {
                        Task {
                            await session.bootstrap()
                            await session.refreshConfig()
                            if session.config.features.enabled {
                                await feed.load(groupId: session.selectedGroupId)
                            }
                        }
                    }
                )
            } else {
                ProgressView()
                    .tint(theme.colors.accent)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        } else if !session.config.features.enabled {
            CommunityEmptyState(
                systemImage: "hourglass",
                title: CommunityStrings.disabledTitle,
                message: CommunityStrings.disabledMessage,
                expandsToFill: true
            )
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
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(spacing: 12) {
                    Color.clear
                        .frame(height: 0)
                        .id("feed-top")

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
                            availableReactions: session.config.features.reactions,
                            onTapPost: { openPost(post) },
                            onTapAuthor: session.config.features.profilesEnabled
                                ? {
                                    guard let author = post.author, author.isAddressable else { return }
                                    selectedProfileId = author.id
                                }
                                : nil,
                            onReact: { kind in
                                Task { await feed.toggleReaction(postId: post.id, kind: kind) }
                            },
                            onComment: { openPost(post) },
                            onMore: { moreActionsPost = post },
                            onVote: { optionId in
                                Task { await feed.voteOnPoll(postId: post.id, optionId: optionId) }
                            }
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
                // Feed first: `.refreshable` cancels when the gesture ends, and a
                // slow bootstrap-first sequence often never reaches the reload.
                await feed.refresh(groupId: session.selectedGroupId)
                proxy.scrollTo("feed-top", anchor: .top)
                await session.bootstrap()
                if let selected = session.selectedGroupId,
                   !session.groups.contains(where: { $0.id == selected }) {
                    session.setSelectedGroup(nil)
                    await feed.refresh(groupId: nil)
                    proxy.scrollTo("feed-top", anchor: .top)
                }
            }
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

extension FeedView {
    private func openPost(_ post: CommunityPost, threadCommentId: String? = nil) {
        openedPost = post
        path.append(PostNavRoute(id: post.id))
        // Reply push: push "Réponses" on the same NavigationStack. Avoid the
        // nested NavigationLink(isActive:) which blanks the detail on cold start.
        if let threadCommentId, !threadCommentId.isEmpty {
            path.append(
                ReplyThreadRoute(
                    postId: post.id,
                    rootCommentId: threadCommentId,
                    fromPushDeeplink: true
                )
            )
        }
    }

    private func resolvedPost(id: String) -> CommunityPost? {
        if let openedPost, openedPost.id == id { return openedPost }
        return feed.posts.first { $0.id == id }
    }

    /// Opens a post from an `appwin://community/post/{id}` push tap.
    ///
    /// Falls back to the all-groups feed when the member was on another tab
    /// and the post is not in the current page. Reply pushes also carry a
    /// thread id so we push the "Réponses" screen on the stack.
    private func openPostFromDeeplink(_ deeplink: CommunityPushTarget) async {
        pendingDeeplink = deeplink
        if openIfPresent(deeplink) { return }
        if session.selectedGroupId != nil {
            session.setSelectedGroup(nil)
            await feed.load(groupId: nil)
            _ = openIfPresent(deeplink)
        }
    }

    private func consumePendingDeeplinkIfPossible() async {
        guard let deeplink = pendingDeeplink else { return }
        if openIfPresent(deeplink) { return }
        if session.selectedGroupId != nil {
            session.setSelectedGroup(nil)
            await feed.load(groupId: nil)
            _ = openIfPresent(deeplink)
        }
    }

    @discardableResult
    private func openIfPresent(_ deeplink: CommunityPushTarget) -> Bool {
        guard let post = feed.posts.first(where: { $0.id == deeplink.postId }) else { return false }
        pendingDeeplink = nil
        // Avoid stacking the same detail if the tap is delivered twice.
        if path.isEmpty || openedPost?.id != deeplink.postId {
            openPost(post, threadCommentId: deeplink.threadCommentId)
        } else if let threadId = deeplink.threadCommentId, !threadId.isEmpty {
            path.append(
                ReplyThreadRoute(
                    postId: post.id,
                    rootCommentId: threadId,
                    fromPushDeeplink: true
                )
            )
        }
        return true
    }
}

/// Hashable route for `NavigationStack` (iOS 16) - the full post is kept in
/// `openedPost` / the feed store, not duplicated into the path.
struct PostNavRoute: Hashable {
    let id: String
}

/// Dedicated replies screen route (push notification reply, or "see replies").
struct ReplyThreadRoute: Hashable {
    let postId: String
    let rootCommentId: String
    /// Push tap: land on the latest reply without opening the keyboard.
    var fromPushDeeplink: Bool = false
}

/// Loads the comment store then hosts `ReplyThreadView` for stack navigation.
struct ReplyThreadDeepLinkHost: View {
    @EnvironmentObject private var session: CommunitySession
    @Environment(\.communityTheme) private var theme

    let postId: String
    let rootCommentId: String
    var fromPushDeeplink: Bool = false

    @StateObject private var comments: CommentStore

    init(postId: String, rootCommentId: String, fromPushDeeplink: Bool = false) {
        self.postId = postId
        self.rootCommentId = rootCommentId
        self.fromPushDeeplink = fromPushDeeplink
        _comments = StateObject(
            wrappedValue: CommentStore(repo: Factory.repository(), postId: postId)
        )
    }

    var body: some View {
        Group {
            if comments.isLoading && comments.comments.isEmpty {
                ProgressView()
                    .tint(theme.colors.accent)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .background(theme.colors.background)
                    .navigationTitle(CommunityStrings.replies)
                    .navigationBarTitleDisplayMode(.inline)
            } else {
                ReplyThreadView(
                    rootCommentId: rootCommentId,
                    comments: comments,
                    onCommentCountChange: { _ in },
                    focusComposerOnAppear: false,
                    scrollToLatestOnAppear: fromPushDeeplink
                )
                .environmentObject(session)
            }
        }
        .task {
            await comments.load()
        }
    }
}

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
