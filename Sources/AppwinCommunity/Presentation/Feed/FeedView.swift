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
    /// Bumped on publish: the new post lands at the top, out of sight when the
    /// member had scrolled down.
    @State private var scrollToTopTick = 0
    @State private var editingPost: CommunityPost?
    @State private var path = NavigationPath()
    @State private var openedPost: CommunityPost?
    @State private var selectedProfileId: String?
    @State private var screen: FeedScreen?
    /// Post id from a push tap, kept until the feed page that contains it loads.
    @State private var pendingDeeplink: CommunityPushTarget?
    @StateObject private var presence = CommunityFeedHandle()
    @ObservedObject private var availability = CommunityAvailability.shared

    var body: some View {
        // Push into the post (back chevron), same as Android's route stack -
        // not a sheet that slides up over the feed.
        NavigationStack(path: $path) {
            ZStack(alignment: .bottom) {
                // The page colour runs edge to edge, under the status bar: the feed
                // is a full-screen tab of the host app, not a sheet floating on a
                // grey mat. Only the content below is inset by the safe area.
                theme.colors.background.communityReactionDimmed().ignoresSafeArea()

                // Pin to the top: a plain VStack inside a ZStack is centred by
                // default, which shrinks error / loading states into a mid-screen
                // island with a large empty band above.
                VStack(spacing: 0) {
                    screenHeader
                        .communityReactionDimmed()
                        .zIndex(1)
                    content
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)

                if session.canPost {
                    composerButton
                        .communityReactionDimmed(cornerRadius: theme.radius.card)
                }
            }
            .communityReactionFocusHost()
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
                scrollToTopTick += 1
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
        .communityContentActions(CommunityActionHandlers(
            onEdit: { editingPost = $0 },
            onPostGone: { feed.remove(postId: $0) },
            onPostUpdated: { feed.replace($0) }
        ))
        .fullScreenCover(item: $screen) { screen in
            Group {
                switch screen {
                case .moderation: ModerationView()
                case .sanctions: SanctionsView()
                }
            }
            .environmentObject(session)
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
            presence.isVisible = true
            if let waiting = CommunityFeedPresence.register(presence) {
                Task { await openPostFromDeeplink(waiting) }
            }
        }
        .onDisappear {
            presence.isVisible = false
            Task { await feed.flushViews() }
        }
        .onReceive(presence.targets) { target in
            Task { await openPostFromDeeplink(target) }
        }
    }

    private var screenHeader: some View {
        FeedScreenHeader(
            showsCloseButton: showsCloseButton,
            onClose: { onClose?() },
            onOpenProfile: { selectedProfileId = session.profile.id },
            onOpen: { screen = $0 }
        )
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
            feedList
        }
    }

    private var feedList: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(spacing: 8) {
                    Color.clear
                        .frame(height: 0)
                        .id("feed-top")

                    #if DEBUG
                    if availability.debugUnlocked {
                        CommunityDebugAlert(diagnosis: .debugUnlocked, theme: theme)
                    }
                    #endif

                    if session.profile.isBanned {
                        bannedNotice
                            // Clears the « Épinglé » badge that rides on the first card.
                            .padding(.bottom, feed.posts.first?.isPinned == true ? 12 : 0)
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
                .padding(.horizontal, 20)
                // Room for a pinned post's badge, which straddles the card's edge.
                .padding(.top, 20)
                // Bottom margin: the floating button must not hide the last post.
                .padding(.bottom, session.canPost ? 104 : 24)
            }
            .onChange(of: scrollToTopTick) { _ in
                withAnimation { proxy.scrollTo("feed-top", anchor: .top) }
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

    /// Floating compose button - Figma feed 5:1999, centred at the bottom.
    private var composerButton: some View {
        Button { composerPresented = true } label: {
            HStack(spacing: 8) {
                CommunityIconView(icon: .penNewSquare, size: 16, color: theme.colors.onAccent)
                Text(CommunityStrings.newPost)
                    .font(theme.font(16, weight: .medium))
            }
            .foregroundStyle(theme.colors.onAccent)
            .padding(.horizontal, 20)
            .frame(height: 56)
            .background(theme.composeFill, in: RoundedRectangle(cornerRadius: theme.radius.card))
            .overlay(
                RoundedRectangle(cornerRadius: theme.radius.card)
                    .strokeBorder(.white.opacity(0.12), lineWidth: 3)
            )
        }
        .buttonStyle(.plain)
        .shadow(color: theme.accentShadow, radius: 20, y: 24)
        .padding(.bottom, 24)
    }
}

/// Group pills - Figma feed toggleGroup: the active pill carries the accent,
/// the others are outlined.
struct GroupTabBar: View {
    @EnvironmentObject private var session: CommunitySession
    @Environment(\.communityTheme) private var theme

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 6) {
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
            .padding(20)
        }
    }

    private func tab(
        title: String,
        isActive: Bool,
        action: @escaping () -> Void
    ) -> some View {
        // The card radius, so the studio's notch reaches the pills too: low
        // gives soft rectangles, max gives capsules.
        let shape = RoundedRectangle(cornerRadius: theme.radius.card)
        return Button(action: action) {
            Text(title)
                .font(theme.font(14, weight: isActive ? .semibold : .medium))
                .foregroundStyle(isActive ? theme.colors.onAccent : theme.colors.textTertiary)
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .background {
                    if isActive {
                        shape.fill(theme.accentFill)
                    } else {
                        shape.strokeBorder(theme.colors.border, lineWidth: 1)
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
        await consumePendingDeeplinkIfPossible()
    }

    private func consumePendingDeeplinkIfPossible() async {
        guard let deeplink = pendingDeeplink else { return }
        if openIfPresent(deeplink) { return }
        if session.selectedGroupId != nil {
            session.setSelectedGroup(nil)
            await feed.load(groupId: nil)
            if openIfPresent(deeplink) { return }
        }
        // Older than the loaded page: fetched on its own.
        guard let post = await CommunityPostLookup.find(postId: deeplink.postId),
              pendingDeeplink == deeplink
        else { return }
        pendingDeeplink = nil
        openPost(post, threadCommentId: deeplink.threadCommentId)
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
