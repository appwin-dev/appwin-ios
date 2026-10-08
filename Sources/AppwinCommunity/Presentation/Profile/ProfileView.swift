import SwiftUI

/// Profile screen - Figma profile (32:5665): the hero (avatar, name, posts
/// and seniority) on the page, then the member's posts as in the feed.
///
/// A member edits their own profile here; on someone else's they can only
/// report. `isMe` is resolved server-side, so there is no id comparison here.
struct ProfileView: View {
    @EnvironmentObject private var session: CommunitySession
    @Environment(\.communityTheme) private var theme
    @Environment(\.dismiss) private var dismiss

    let profileId: String
    var onCompose: (() -> Void)? = nil

    @State private var profile: CommunityProfile?
    @State private var isEditing = false
    @State private var showsAvatarViewer = false
    @State private var editingPost: CommunityPost?
    @State private var errorMessage: String?
    @StateObject private var publications = ProfilePostsStore()
    @State private var path = NavigationPath()
    @State private var openedPost: CommunityPost?

    var body: some View {
        NavigationStack(path: $path) {
            ScrollView {
                if let profile {
                    content(profile)
                } else if errorMessage != nil {
                    CommunityEmptyState(
                        systemImage: "exclamationmark.triangle",
                        title: CommunityStrings.loadErrorTitle,
                        message: CommunityStrings.loadErrorMessage,
                        actionTitle: CommunityStrings.retry,
                        action: { Task { await load() } }
                    )
                } else {
                    ProgressView().tint(theme.colors.accent).padding(theme.spacing.xxl)
                }
            }
            .background(theme.colors.background.communityReactionDimmed().ignoresSafeArea())
            .communityReactionFocusHost()
            .toolbar(.hidden, for: .navigationBar)
            .navigationDestination(for: PostNavRoute.self) { route in
                if let post = resolvedPost(id: route.id) {
                    PostDetailView(
                        post: post,
                        onCommentCountChange: { delta in
                            publications.patchCommentCount(postId: post.id, delta: delta)
                        },
                        onDeleted: { publications.remove(postId: post.id) },
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
        .sheet(isPresented: $isEditing) {
            if let profile {
                EditProfileView(profile: profile) { updated in
                    self.profile = updated
                    session.applyProfile(updated)
                }
                .environmentObject(session)
            }
        }
        .sheet(item: $editingPost) { post in
            ComposerView(editingPost: post) { updated in
                publications.replace(updated)
            }
            .environmentObject(session)
        }
        .communityContentActions(CommunityActionHandlers(
            onEdit: { editingPost = $0 },
            onPostGone: { publications.remove(postId: $0) },
            onPostUpdated: { publications.replace($0) }
        ))
        .task {
            await load()
            await publications.load(authorProfileId: profileId)
        }
        // A host editor (`onEditProfile`) saves through `setUser`, behind this
        // sheet's back.
        .onReceive(NotificationCenter.default.publisher(for: .appwinCommunityUiRefresh)) { _ in
            Task { await load() }
        }
    }

    private func content(_ profile: CommunityProfile) -> some View {
        VStack(spacing: 20) {
            hero(profile).communityReactionDimmed()
            publicationsSection(isMe: profile.isMe)
            Spacer(minLength: theme.spacing.xxl)
        }
    }

    private func hero(_ profile: CommunityProfile) -> some View {
        VStack(spacing: 20) {
            HStack {
                CommunityGlassButton(systemImage: "chevron.left", accessibilityLabel: CommunityStrings.close) {
                    dismiss()
                }
                Spacer(minLength: 0)
                profileMenu(profile)
            }
            .padding(.horizontal, 20)

            VStack(spacing: 16) {
                avatarButton(profile)

                HStack(spacing: 8) {
                    Text(profile.nickname)
                        .font(theme.font(24, weight: .medium))
                        .foregroundStyle(theme.colors.textPrimary)
                        .lineLimit(1)
                    if profile.isTeam {
                        CommunityTeamBadge()
                    }
                }
            }

            HStack(spacing: 4) {
                statPill(value: "\(profile.postCount)", label: CommunityStrings.publications)
                statPill(value: seniority(since: profile.joinedAt), label: CommunityStrings.seniority)
            }

            if let bio = profile.bio, !bio.isEmpty {
                Text(bio)
                    .font(theme.font(14))
                    .foregroundStyle(theme.colors.textSecondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 20)
            }
        }
        .padding(.top, 16)
        .padding(.bottom, 20)
        .frame(maxWidth: .infinity)
        .background(alignment: .topLeading) {
            theme.colors.background
                .overlay(alignment: .topLeading) { CommunityAccentGlow() }
                .clipped()
        }
        .compositingGroup()
        .shadow(color: .black.opacity(0.08), radius: 20, y: 24)
    }

    /// Figma avatar: 88pt with a 3pt ring in the accent.
    private func avatarButton(_ profile: CommunityProfile) -> some View {
        Button {
            if profile.avatarUrl != nil {
                showsAvatarViewer = true
            } else if profile.isMe {
                CommunityProfileEditing.begin { isEditing = true }
            }
        } label: {
            CommunityAvatar(url: profile.avatarUrl, nickname: profile.nickname, size: 88)
                .overlay(Circle().strokeBorder(theme.colors.accent, lineWidth: 3))
                .overlay(alignment: .bottomTrailing) {
                    if profile.role == .admin || profile.isTeam {
                        CommunityAdminBadge(avatarSize: 72)
                    }
                }
        }
        .buttonStyle(.plain)
        // Tappable when there is a photo to enlarge, or when it is me (edit).
        .disabled(profile.avatarUrl == nil && !profile.isMe)
        .accessibilityLabel(
            profile.avatarUrl == nil && profile.isMe ? CommunityStrings.editProfile : profile.nickname
        )
        .fullScreenCover(isPresented: $showsAvatarViewer) {
            if let url = profile.avatarUrl {
                CommunityImageViewer(url: url)
            }
        }
    }

    /// Figma draws only the dots: editing (mine); reporting, or sanctions for
    /// moderators (theirs).
    @ViewBuilder
    private func profileMenu(_ profile: CommunityProfile) -> some View {
        let actsOnOthers = session.config.features.reportingEnabled || session.profile.canModerate
        if profile.isMe {
            Menu {
                Button(CommunityStrings.editProfile) {
                    CommunityProfileEditing.begin { isEditing = true }
                }
            } label: { dots }
        } else if actsOnOthers {
            CommunityActionsMenu(target: .member(CommunityAuthor(
                id: profile.id,
                nickname: profile.nickname,
                avatarUrl: profile.avatarUrl,
                role: profile.role,
                isTeam: profile.isTeam
            ))) { dots }
        }
    }

    private var dots: some View {
        Image(systemName: "ellipsis")
            .font(.system(size: 17, weight: .semibold))
            .foregroundStyle(theme.colors.textTertiary)
            .frame(width: 38, height: 38)
    }

    /// Figma data pill: bg/brand-soft, value over label.
    private func statPill(value: String, label: String) -> some View {
        VStack(spacing: 1) {
            Text(value)
                .font(theme.font(14, weight: .semibold))
            Text(label)
                .font(theme.font(12))
        }
        .foregroundStyle(theme.colors.textPrimary)
        .lineLimit(1)
        .frame(width: 144)
        .padding(.vertical, 8)
        .background(theme.colors.accent.opacity(0.24), in: RoundedRectangle(cornerRadius: theme.radius.field))
    }

    /// "4 ans", "3 mois": the largest unit only, in the device language.
    private func seniority(since joinedAt: Date) -> String {
        let formatter = DateComponentsFormatter()
        formatter.unitsStyle = .full
        formatter.maximumUnitCount = 1
        formatter.allowedUnits = [.year, .month, .day]
        return formatter.string(from: joinedAt, to: Date()) ?? ""
    }

    @ViewBuilder
    private func publicationsSection(isMe: Bool) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            if publications.isLoading && publications.posts.isEmpty {
                ProgressView().tint(theme.colors.accent)
                    .frame(maxWidth: .infinity)
                    .padding(theme.spacing.xl)
            } else if publications.posts.isEmpty {
                CommunityEmptyState(
                    systemImage: "square.and.pencil",
                    title: isMe
                        ? CommunityStrings.noPublicationsYet
                        : CommunityStrings.noPublicationsOther,
                    actionTitle: isMe ? CommunityStrings.createFirstPost : nil,
                    action: isMe ? {
                        dismiss()
                        onCompose?()
                    } : nil
                )
            } else {
                LazyVStack(spacing: 8) {
                    ForEach(publications.posts) { post in
                        PostCard(
                            post: post,
                            showTranslation: session.config.features.translationEnabled,
                            canReact: session.config.features.reactionsEnabled,
                            showViews: session.config.features.viewsEnabled,
                            availableReactions: session.config.features.reactions,
                            onTapPost: { openPost(post) },
                            onTapAuthor: nil,
                            onReact: { kind in
                                Task { await publications.toggleReaction(postId: post.id, kind: kind) }
                            },
                            onComment: { openPost(post) }
                        )
                        .padding(.horizontal, 20)
                        .onAppear {
                            if post.id == publications.posts.last?.id {
                                Task { await publications.loadMore() }
                            }
                        }
                    }
                }
            }
        }
    }

    private func openPost(_ post: CommunityPost) {
        openedPost = post
        path.append(PostNavRoute(id: post.id))
    }

    private func resolvedPost(id: String) -> CommunityPost? {
        if let openedPost, openedPost.id == id { return openedPost }
        return publications.posts.first { $0.id == id }
    }

    private func load() async {
        do {
            profile = try await Factory.repository().profile(profileId: profileId)
            errorMessage = nil
        } catch {
            errorMessage = String(describing: error)
        }
    }
}
