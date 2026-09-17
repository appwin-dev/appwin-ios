import SwiftUI
import PhotosUI
import UniformTypeIdentifiers

/// Profile screen: identity, join date, counters, publications.
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
    @State private var reportTarget: ReportTarget?
    @State private var errorMessage: String?
    @StateObject private var publications = ProfilePostsStore()
    @State private var selectedPost: CommunityPost?

    var body: some View {
        NavigationStack {
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
            .navigationTitle(CommunityStrings.profile)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button(CommunityStrings.close) { dismiss() }
                        .foregroundStyle(theme.colors.accent)
                }
                ToolbarItem(placement: .topBarTrailing) {
                    if let profile, !profile.isMe, session.config.features.reportingEnabled {
                        Button(CommunityStrings.report) {
                            reportTarget = ReportTarget(type: "profile", id: profile.id)
                        }
                        .foregroundStyle(theme.colors.danger)
                    }
                }
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
        .sheet(item: $selectedPost) { post in
            PostDetailView(post: post) { delta in
                publications.patchCommentCount(postId: post.id, delta: delta)
            }
            .environmentObject(session)
        }
        .task {
            await load()
            await publications.load(authorProfileId: profileId)
        }
    }

    private func content(_ profile: CommunityProfile) -> some View {
        VStack(spacing: theme.spacing.lg) {
            profileHeader(profile)

            if let bio = profile.bio, !bio.isEmpty {
                Text(bio)
                    .font(theme.font(14))
                    .foregroundStyle(theme.colors.textSecondary)
                    .multilineTextAlignment(.leading)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, theme.spacing.lg)
            }

            if profile.isMe {
                profileActions(profile)
            }

            publicationsSection(isMe: profile.isMe)

            Spacer(minLength: theme.spacing.xxl)
        }
    }

    private func profileHeader(_ profile: CommunityProfile) -> some View {
        HStack(alignment: .center, spacing: 16) {
            Button {
                if profile.isMe { isEditing = true }
            } label: {
                ZStack(alignment: .bottomTrailing) {
                    CommunityAvatar(
                        url: profile.avatarUrl,
                        nickname: profile.nickname,
                        size: 72
                    )
                    if profile.isMe {
                        Image(systemName: "plus")
                            .font(.system(size: 11, weight: .bold))
                            .foregroundStyle(theme.colors.onAccent)
                            .frame(width: 22, height: 22)
                            .background(theme.colors.accent, in: Circle())
                            .overlay(Circle().stroke(theme.colors.background, lineWidth: 2))
                            .offset(x: 2, y: 2)
                    }
                }
            }
            .buttonStyle(.plain)
            .disabled(!profile.isMe)
            .accessibilityLabel(
                profile.isMe ? CommunityStrings.editProfile : profile.nickname
            )

            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 8) {
                    Text(profile.nickname)
                        .font(theme.font(20, weight: .bold))
                        .foregroundStyle(theme.colors.textPrimary)
                        .lineLimit(1)
                    if profile.isTeam {
                        CommunityTeamBadge()
                    }
                }

                Text(
                    [
                        CommunityStrings.postCount(profile.postCount),
                        String(
                            format: CommunityStrings.memberSince,
                            profile.joinedAt.formatted(.dateTime.month(.abbreviated).year())
                        ),
                    ].joined(separator: "  ·  ")
                )
                .font(theme.font(13))
                .foregroundStyle(theme.colors.textTertiary)
                .lineLimit(2)
            }

            Spacer(minLength: 0)
        }
        .padding(.horizontal, theme.spacing.lg)
        .padding(.top, theme.spacing.lg)
    }

    private func profileActions(_ profile: CommunityProfile) -> some View {
        HStack(spacing: 10) {
            profileActionPill(
                title: "+\(CommunityStrings.addBio)",
                action: { isEditing = true }
            )
            profileActionPill(
                title: CommunityStrings.editProfile,
                action: { isEditing = true }
            )
        }
        .padding(.horizontal, theme.spacing.lg)
    }

    private func profileActionPill(title: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title)
                .font(theme.font(13, weight: .medium))
                .foregroundStyle(theme.colors.textPrimary)
                .lineLimit(1)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 10)
                .padding(.horizontal, 12)
                .background(
                    Capsule()
                        .strokeBorder(theme.colors.border, lineWidth: 1)
                        .background(Capsule().fill(theme.colors.background))
                )
        }
        .buttonStyle(.plain)
    }

    @ViewBuilder
    private func publicationsSection(isMe: Bool) -> some View {
        VStack(alignment: .leading, spacing: theme.spacing.md) {
            Text(CommunityStrings.publications)
                .font(theme.font(15, weight: .semibold))
                .foregroundStyle(theme.colors.textPrimary)
                .padding(.horizontal, theme.spacing.md)

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
                LazyVStack(spacing: theme.spacing.md) {
                    ForEach(publications.posts) { post in
                        PostCard(
                            post: post,
                            showTranslation: session.config.features.translationEnabled,
                            canReact: session.config.features.reactionsEnabled,
                            showViews: session.config.features.viewsEnabled,
                            availableReactions: session.config.features.reactions,
                            onTapPost: { selectedPost = post },
                            onTapAuthor: {},
                            onReact: { kind in
                                Task { await publications.toggleReaction(postId: post.id, kind: kind) }
                            },
                            onComment: { selectedPost = post },
                            onMore: {}
                        )
                        .padding(.horizontal, theme.spacing.md)
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

    private func load() async {
        do {
            profile = try await Factory.repository().profile(profileId: profileId)
            errorMessage = nil
        } catch {
            errorMessage = String(describing: error)
        }
    }
}

/// Editing your own profile (avatar, nickname, bio).
///
/// Layout mirrors common community "Edition" screens: large avatar with an
/// edit badge, labelled bordered fields, and a pill Save in the nav bar.
struct EditProfileView: View {
    @EnvironmentObject private var session: CommunitySession
    @Environment(\.communityTheme) private var theme
    @Environment(\.dismiss) private var dismiss

    let profile: CommunityProfile
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

    init(profile: CommunityProfile, onSaved: @escaping (CommunityProfile) -> Void) {
        self.profile = profile
        self.onSaved = onSaved
        _nickname = State(initialValue: profile.isAnonymous ? "" : profile.nickname)
        _bio = State(initialValue: profile.bio ?? "")
        _isAnonymous = State(initialValue: profile.isAnonymous)
        _avatarUrl = State(initialValue: profile.avatarUrl)
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 28) {
                    avatarPicker
                        .padding(.top, 8)

                    VStack(alignment: .leading, spacing: 20) {
                        if !isAnonymous {
                            fieldBlock(label: CommunityStrings.nickname) {
                                TextField(CommunityStrings.nickname, text: $nickname)
                                    .focused($focusedField, equals: .nickname)
                                    .textInputAutocapitalization(.words)
                                    .font(theme.font(15))
                                    .foregroundStyle(theme.colors.textPrimary)
                                    .padding(.horizontal, 14)
                                    .padding(.vertical, 14)
                            } footer: {
                                Text(CommunityStrings.nicknameHelp)
                                    .font(theme.font(12))
                                    .foregroundStyle(theme.colors.textTertiary)
                                    .fixedSize(horizontal: false, vertical: true)
                            }
                        }

                        fieldBlock(label: CommunityStrings.bio) {
                            ZStack(alignment: .topLeading) {
                                if bio.isEmpty {
                                    Text(CommunityStrings.bioPlaceholder)
                                        .font(theme.font(15))
                                        .foregroundStyle(theme.colors.textTertiary)
                                        .padding(.horizontal, 14)
                                        .padding(.vertical, 14)
                                        .allowsHitTesting(false)
                                }
                                TextField("", text: $bio, axis: .vertical)
                                    .focused($focusedField, equals: .bio)
                                    .font(theme.font(15))
                                    .foregroundStyle(theme.colors.textPrimary)
                                    .lineLimit(5...10)
                                    .padding(.horizontal, 14)
                                    .padding(.vertical, 14)
                                    .onChange(of: bio) { value in
                                        if value.count > bioLimit {
                                            bio = String(value.prefix(bioLimit))
                                        }
                                    }
                            }
                            .frame(minHeight: 120, alignment: .topLeading)
                        } footer: {
                            Text(String(format: CommunityStrings.bioCounter, bio.count, bioLimit))
                                .font(theme.font(12))
                                .foregroundStyle(theme.colors.textTertiary)
                                .frame(maxWidth: .infinity, alignment: .trailing)
                        }

                        Toggle(CommunityStrings.anonymous, isOn: $isAnonymous)
                            .font(theme.font(14))
                            .tint(theme.colors.accent)
                            .padding(.top, 4)
                    }

                    if let errorMessage {
                        Text(errorMessage)
                            .font(theme.font(13))
                            .foregroundStyle(theme.colors.danger)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                }
                .padding(.horizontal, 20)
                .padding(.bottom, 32)
            }
            .background(theme.colors.background)
            .navigationTitle(CommunityStrings.editProfileTitle)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button { dismiss() } label: {
                        Image(systemName: "chevron.left")
                            .font(.system(size: 15, weight: .semibold))
                            .foregroundStyle(theme.colors.textPrimary)
                            .frame(width: 36, height: 36)
                            .background(theme.colors.surface, in: Circle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(CommunityStrings.cancel)
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button(action: save) {
                        Text(CommunityStrings.save)
                            .font(theme.font(14, weight: .semibold))
                            .foregroundStyle(
                                canSave
                                    ? theme.colors.onAccent
                                    : theme.colors.onAccent.opacity(0.55)
                            )
                            .padding(.horizontal, 14)
                            .padding(.vertical, 8)
                            .background {
                                Capsule().fill(
                                    canSave
                                        ? theme.composeFill
                                        : AnyShapeStyle(theme.colors.accent.opacity(0.4))
                                )
                            }
                    }
                    .buttonStyle(.plain)
                    .disabled(!canSave)
                }
            }
            .onChange(of: pickerItem) { item in
                guard let item else { return }
                Task { await uploadAvatar(item) }
            }
        }
    }

    private func fieldBlock<Content: View, Footer: View>(
        label: String,
        @ViewBuilder content: () -> Content,
        @ViewBuilder footer: () -> Footer
    ) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(label)
                .font(theme.font(13, weight: .medium))
                .foregroundStyle(theme.colors.textSecondary)
            content()
                .background(theme.colors.background)
                .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .strokeBorder(theme.colors.border, lineWidth: 1)
                )
            footer()
        }
    }

    private var avatarPicker: some View {
        PhotosPicker(selection: $pickerItem, matching: .images, photoLibrary: .shared()) {
            ZStack(alignment: .bottomTrailing) {
                CommunityAvatar(
                    url: avatarUrl,
                    nickname: nickname.isEmpty ? profile.nickname : nickname,
                    size: 112
                )
                Image(systemName: "pencil")
                    .font(.system(size: 12, weight: .bold))
                    .foregroundStyle(theme.colors.onAccent)
                    .frame(width: 28, height: 28)
                    .background(theme.colors.accent, in: Circle())
                    .overlay(Circle().stroke(theme.colors.background, lineWidth: 2))
                    .offset(x: 2, y: 2)
                if isUploadingAvatar {
                    ProgressView()
                        .tint(theme.colors.onAccent)
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
            let uploaded = try await Factory.repository().uploadMedia(
                data: data,
                mimeType: "image/jpeg",
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
