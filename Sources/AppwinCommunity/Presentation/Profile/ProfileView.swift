import SwiftUI
import PhotosUI
import AppwinCore
import UniformTypeIdentifiers

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
    @State private var reportTarget: ReportTarget?
    @State private var moreActionsPost: CommunityPost?
    @State private var editingPost: CommunityPost?
    @State private var pendingDeletion: CommunityPost?
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
            .background(theme.colors.background)
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
        .sheet(item: $reportTarget) { target in
            ReportSheet(target: target).environmentObject(session)
        }
        .sheet(item: $editingPost) { post in
            ComposerView(editingPost: post) { updated in
                publications.replace(updated)
            }
            .environmentObject(session)
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
                if session.config.features.reportingEnabled, !post.canEdit {
                    Button(CommunityStrings.report) {
                        reportTarget = ReportTarget(type: "post", id: post.id)
                    }
                }
                Button(CommunityStrings.cancel, role: .cancel) {}
            }
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
                if let post = pendingDeletion {
                    Task {
                        publications.remove(postId: post.id)
                        try? await Factory.repository().deletePost(postId: post.id)
                    }
                }
            }
            Button(CommunityStrings.cancel, role: .cancel) {}
        } message: {
            Text(CommunityStrings.deletePostMessage)
        }
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
            hero(profile)
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

    /// Figma draws only the dots: editing (mine) and reporting (theirs) live there.
    @ViewBuilder
    private func profileMenu(_ profile: CommunityProfile) -> some View {
        let canReport = !profile.isMe && session.config.features.reportingEnabled
        if profile.isMe || canReport {
            Menu {
                if profile.isMe {
                    Button(CommunityStrings.editProfile) {
                        CommunityProfileEditing.begin { isEditing = true }
                    }
                }
                if canReport {
                    Button(CommunityStrings.report, role: .destructive) {
                        reportTarget = ReportTarget(type: "profile", id: profile.id)
                    }
                }
            } label: {
                Image(systemName: "ellipsis")
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundStyle(theme.colors.textTertiary)
                    .frame(width: 38, height: 38)
            }
        }
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
                            onComment: { openPost(post) },
                            onMore: { moreActionsPost = post }
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

/// Editing your own profile - Figma edit-profil (19:4345 / 19:4497): the
/// avatar with its pencil badge, the name, the bio and the anonymity switch.
///
/// Figma shows the name read-only; the nickname stays editable below it, since
/// a member leaving anonymity has to set one somewhere.
struct EditProfileView: View {
    @EnvironmentObject private var session: CommunitySession
    @Environment(\.communityTheme) private var theme
    @Environment(\.dismiss) private var dismiss

    let profile: CommunityProfile
    /// When true (composer CTA), open with anonymity already off so the member
    /// can set a nickname without hunting for the toggle.
    var leaveAnonymity: Bool = false
    let onSaved: (CommunityProfile) -> Void

    @State private var nickname: String
    @State private var bio: String
    @State private var isAnonymous: Bool
    @State private var avatarUrl: URL?
    @State private var pickerItem: PhotosPickerItem?
    @State private var isUploadingAvatar = false
    @State private var isSaving = false
    @State private var errorMessage: String?
    @FocusState private var focusedField: Field?

    private enum Field { case nickname, bio }

    private let bioLimit = 200

    private var canSave: Bool {
        !isSaving
            && !isUploadingAvatar
            && (isAnonymous || nickname.trimmingCharacters(in: .whitespaces).count >= 2)
    }

    init(
        profile: CommunityProfile,
        leaveAnonymity: Bool = false,
        onSaved: @escaping (CommunityProfile) -> Void
    ) {
        self.profile = profile
        self.leaveAnonymity = leaveAnonymity
        self.onSaved = onSaved
        _nickname = State(initialValue: profile.isAnonymous ? "" : profile.nickname)
        _bio = State(initialValue: profile.bio ?? "")
        _isAnonymous = State(initialValue: leaveAnonymity ? false : profile.isAnonymous)
        _avatarUrl = State(initialValue: profile.avatarUrl)
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                CommunityNavHeader(
                    leadingTitle: CommunityStrings.cancel,
                    onLeading: { dismiss() },
                    title: CommunityStrings.editProfileTitle,
                    verticalPadding: 16
                ) {
                    CommunityBrandPill(
                        title: CommunityStrings.save,
                        fontSize: 12,
                        isEnabled: canSave,
                        isLoading: isSaving,
                        action: save
                    )
                }

                ScrollView {
                    VStack(spacing: 72) {
                        VStack(spacing: 24) {
                            avatarPicker

                            Text(displayName)
                                .font(theme.font(24, weight: .medium))
                                .foregroundStyle(theme.colors.textPrimary)
                                .lineLimit(1)

                            if !isAnonymous {
                                fieldBlock(label: CommunityStrings.nickname) {
                                    TextField(CommunityStrings.nickname, text: $nickname)
                                        .focused($focusedField, equals: .nickname)
                                        .textInputAutocapitalization(.words)
                                        .font(theme.font(14))
                                        .foregroundStyle(theme.colors.textPrimary)
                                        .padding(20)
                                } trailing: {
                                    EmptyView()
                                }
                            }

                            fieldBlock(label: CommunityStrings.bio) {
                                ZStack(alignment: .topLeading) {
                                    if bio.isEmpty {
                                        Text(CommunityStrings.bioPlaceholder)
                                            .font(theme.font(14))
                                            .foregroundStyle(theme.colors.textTertiary)
                                            .allowsHitTesting(false)
                                    }
                                    TextField("", text: $bio, axis: .vertical)
                                        .focused($focusedField, equals: .bio)
                                        .font(theme.font(14))
                                        .foregroundStyle(theme.colors.textPrimary)
                                        .lineLimit(4...8)
                                        .onChange(of: bio) { value in
                                            if value.count > bioLimit {
                                                bio = String(value.prefix(bioLimit))
                                            }
                                        }
                                }
                                .padding(20)
                                .frame(minHeight: 120, alignment: .topLeading)
                            } trailing: {
                                Text(String(format: CommunityStrings.bioCounter, bio.count, bioLimit))
                                    .font(theme.font(10, weight: .bold))
                                    .foregroundStyle(theme.colors.textTertiary)
                            }
                        }

                        HStack(alignment: .top, spacing: 16) {
                            VStack(alignment: .leading, spacing: 8) {
                                Text(CommunityStrings.anonymous)
                                    .font(theme.font(14, weight: .medium))
                                    .foregroundStyle(theme.colors.textPrimary)
                                Text(CommunityStrings.anonymousHint)
                                    .font(theme.font(14))
                                    .foregroundStyle(theme.colors.textTertiary)
                                    .fixedSize(horizontal: false, vertical: true)
                            }
                            Spacer(minLength: 0)
                            Toggle("", isOn: $isAnonymous)
                                .labelsHidden()
                                .tint(theme.colors.accent)
                                .accessibilityLabel(CommunityStrings.anonymous)
                        }

                        if let errorMessage {
                            Text(errorMessage)
                                .font(theme.font(13))
                                .foregroundStyle(theme.colors.danger)
                                .frame(maxWidth: .infinity, alignment: .leading)
                        }
                    }
                    .padding(.horizontal, 20)
                    .padding(.top, 16)
                    .padding(.bottom, 32)
                }
            }
            .background(theme.colors.background)
            .toolbar(.hidden, for: .navigationBar)
            .onChange(of: pickerItem) { item in
                guard let item else { return }
                // The API drops the photo of an anonymous profile (anonymity
                // must be visible), so choosing one is choosing to show up.
                isAnonymous = false
                Task { await uploadAvatar(item) }
            }
            .onChange(of: isAnonymous) { anonymous in
                if anonymous { avatarUrl = nil }
            }
        }
    }

    private var displayName: String {
        let typed = nickname.trimmingCharacters(in: .whitespaces)
        return typed.isEmpty ? profile.nickname : typed
    }

    /// Figma input/text-area: label and counter above a white field.
    private func fieldBlock<Content: View, Trailing: View>(
        label: String,
        @ViewBuilder content: () -> Content,
        @ViewBuilder trailing: () -> Trailing
    ) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .firstTextBaseline) {
                Text(label)
                    .font(theme.font(14, weight: .medium))
                    .foregroundStyle(theme.colors.textPrimary)
                Spacer(minLength: 0)
                trailing()
            }
            content()
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(theme.colors.surface, in: RoundedRectangle(cornerRadius: theme.radius.card))
        }
    }

    /// 112pt avatar with the Figma pencil badge (white square, soft shadow).
    private var avatarPicker: some View {
        PhotosPicker(selection: $pickerItem, matching: .images, photoLibrary: .shared()) {
            ZStack(alignment: .bottomTrailing) {
                CommunityAvatar(url: avatarUrl, nickname: displayName, size: 112)
                Image(systemName: "pencil")
                    .font(.system(size: 14, weight: .medium))
                    .foregroundStyle(theme.colors.textPrimary)
                    .frame(width: 32, height: 32)
                    .background(theme.colors.surface, in: RoundedRectangle(cornerRadius: theme.radius.field))
                    .shadow(color: .black.opacity(0.1), radius: 4, y: 4)
                    .offset(x: 0, y: 0)
                if isUploadingAvatar {
                    ProgressView()
                        .tint(.white)
                        .frame(width: 112, height: 112)
                        .background(.black.opacity(0.35), in: Circle())
                }
            }
        }
        .buttonStyle(.plain)
        .disabled(isUploadingAvatar)
        .frame(maxWidth: .infinity)
        .accessibilityLabel(CommunityStrings.addPhoto)
    }

    private func uploadAvatar(_ item: PhotosPickerItem) async {
        isUploadingAvatar = true
        errorMessage = nil
        defer { isUploadingAvatar = false }
        do {
            guard let data = try await item.loadTransferable(type: Data.self) else { return }
            // Avatars are shown at 40-112pt: ship a small JPEG, not the camera
            // original (otherwise every PostCard downloads a multi-MB file).
            let inputMime = item.supportedContentTypes.first?.preferredMIMEType ?? "image/jpeg"
            let compressed = try await ImageCompressor.compress(
                data: data,
                inputMimeType: inputMime,
                options: MediaCompressionOptions(maxDimension: 512, jpegQuality: 0.8)
            )
            let uploaded = try await Factory.repository().uploadMedia(
                data: compressed.data,
                mimeType: compressed.mimeType,
                filename: "avatar.jpg",
                width: nil,
                height: nil
            )
            avatarUrl = uploaded.publicUrl
        } catch {
            errorMessage = String(describing: error)
        }
    }

    private func save() {
        guard canSave else { return }
        isSaving = true
        errorMessage = nil
        Task {
            do {
                let updated = try await Factory.repository().updateOwnProfile(
                    nickname: isAnonymous ? nil : nickname.trimmingCharacters(in: .whitespaces),
                    bio: bio.trimmingCharacters(in: .whitespaces),
                    avatarUrl: avatarUrl?.absoluteString,
                    isAnonymous: isAnonymous
                )
                onSaved(updated)
                dismiss()
            } catch {
                errorMessage = String(describing: error)
            }
            isSaving = false
        }
    }
}

/// Feuille de signalement.
struct ReportSheet: View {
    @Environment(\.communityTheme) private var theme
    @Environment(\.dismiss) private var dismiss

    let target: ReportTarget

    @State private var reason: CommunityReportReason = .spam
    @State private var note = ""
    @State private var isSending = false
    @State private var isSent = false

    var body: some View {
        NavigationStack {
            Form {
                if isSent {
                    Section {
                        Text(CommunityStrings.reportSent)
                            .font(theme.font(14))
                            .foregroundStyle(theme.colors.textSecondary)
                    }
                } else {
                    Section {
                        Picker(CommunityStrings.reportTitle, selection: $reason) {
                            ForEach(CommunityReportReason.allCases, id: \.self) { value in
                                Text(CommunityStrings.reportReason(value)).tag(value)
                            }
                        }
                        .pickerStyle(.inline)
                        .labelsHidden()
                    }

                    Section {
                        TextField("", text: $note, axis: .vertical).lineLimit(2...5)
                    }
                }
            }
            .navigationTitle(CommunityStrings.reportTitle)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button(CommunityStrings.cancel) { dismiss() }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    if !isSent {
                        Button(CommunityStrings.report, action: submit).disabled(isSending)
                    }
                }
            }
        }
    }

    private func submit() {
        isSending = true
        Task {
            try? await Factory.repository().report(
                targetType: target.type,
                targetId: target.targetId,
                reason: reason,
                note: note.isEmpty ? nil : note
            )
            isSent = true
            isSending = false
            try? await Task.sleep(nanoseconds: 1_200_000_000)
            dismiss()
        }
    }
}
