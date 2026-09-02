import SwiftUI

/// Profile screen: identity, join date, counters.
///
/// A member edits their own profile here; on someone else's they can only
/// report. `isMe` is resolved server-side, so there is no id comparison here.
struct ProfileView: View {
    @EnvironmentObject private var session: CommunitySession
    @Environment(\.communityTheme) private var theme
    @Environment(\.dismiss) private var dismiss

    let profileId: String

    @State private var profile: CommunityProfile?
    @State private var isEditing = false
    @State private var reportTarget: ReportTarget?
    @State private var errorMessage: String?

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
                    if let profile {
                        if profile.isMe {
                            Button(CommunityStrings.editProfile) { isEditing = true }
                                .foregroundStyle(theme.colors.accent)
                        } else if session.config.features.reportingEnabled {
                            Button(CommunityStrings.report) {
                                reportTarget = ReportTarget(type: "profile", id: profile.id)
                            }
                            .foregroundStyle(theme.colors.danger)
                        }
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
        .task { await load() }
    }

    private func content(_ profile: CommunityProfile) -> some View {
        VStack(spacing: theme.spacing.lg) {
            CommunityAvatar(url: profile.avatarUrl, nickname: profile.nickname, size: 88)
                .padding(.top, theme.spacing.lg)

            VStack(spacing: 6) {
                HStack(spacing: 8) {
                    Text(profile.nickname)
                        .font(theme.font(20, weight: .semibold))
                        .foregroundStyle(theme.colors.textPrimary)
                    if profile.isTeam {
                        CommunityTeamBadge()
                    }
                }

                Text(String(
                    format: CommunityStrings.memberSince,
                    profile.joinedAt.formatted(.dateTime.month(.wide).year())
                ))
                .font(theme.font(13))
                .foregroundStyle(theme.colors.textTertiary)
            }

            if let bio = profile.bio, !bio.isEmpty {
                Text(bio)
                    .font(theme.font(14))
                    .foregroundStyle(theme.colors.textSecondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, theme.spacing.xl)
            }

            HStack(spacing: 0) {
                stat(value: profile.postCount, label: CommunityStrings.postCount(profile.postCount))
                divider
                stat(
                    value: profile.commentCount,
                    label: CommunityStrings.commentCount(profile.commentCount)
                )
                divider
                stat(
                    value: profile.receivedReactionCount,
                    label: CommunityStrings.reactionCount(profile.receivedReactionCount)
                )
            }
            .padding(theme.spacing.lg)
            .background(
                theme.colors.surface,
                in: RoundedRectangle(cornerRadius: theme.radius.card)
            )
            .padding(.horizontal, theme.spacing.md)

            // A profile with no posts shows an empty state rather than a blank
            // area.
            if profile.postCount == 0 {
                CommunityEmptyState(
                    systemImage: "cat",
                    title: CommunityStrings.noPostsYet
                )
            }

            Spacer(minLength: theme.spacing.xxl)
        }
    }

    private func stat(value: Int, label: String) -> some View {
        VStack(spacing: 2) {
            Text("\(value)")
                .font(theme.font(18, weight: .semibold))
                .foregroundStyle(theme.colors.textPrimary)
            // The pluralised label already carries the number, so keep only the
            // words to avoid showing it twice.
            Text(label.replacingOccurrences(of: "\(value)", with: "").trimmingCharacters(in: .whitespaces))
                .font(theme.font(11))
                .foregroundStyle(theme.colors.textTertiary)
        }
        .frame(maxWidth: .infinity)
    }

    private var divider: some View {
        Rectangle()
            .fill(theme.colors.border)
            .frame(width: 1, height: 28)
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

/// Editing your own profile.
struct EditProfileView: View {
    @Environment(\.communityTheme) private var theme
    @Environment(\.dismiss) private var dismiss

    let profile: CommunityProfile
    let onSaved: (CommunityProfile) -> Void

    @State private var nickname: String
    @State private var bio: String
    @State private var isAnonymous: Bool
    @State private var isSaving = false
    @State private var errorMessage: String?

    init(profile: CommunityProfile, onSaved: @escaping (CommunityProfile) -> Void) {
        self.profile = profile
        self.onSaved = onSaved
        _nickname = State(initialValue: profile.isAnonymous ? "" : profile.nickname)
        _bio = State(initialValue: profile.bio ?? "")
        _isAnonymous = State(initialValue: profile.isAnonymous)
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Toggle(CommunityStrings.anonymous, isOn: $isAnonymous)
                }

                if !isAnonymous {
                    Section(CommunityStrings.nickname) {
                        TextField(CommunityStrings.nickname, text: $nickname)
                            .textInputAutocapitalization(.words)
                    }
                }

                Section(CommunityStrings.bio) {
                    TextField(CommunityStrings.bio, text: $bio, axis: .vertical)
                        .lineLimit(3...6)
                }

                if let errorMessage {
                    Section {
                        Text(errorMessage)
                            .font(theme.font(13))
                            .foregroundStyle(theme.colors.danger)
                    }
                }
            }
            .navigationTitle(CommunityStrings.editProfile)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button(CommunityStrings.cancel) { dismiss() }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button(CommunityStrings.save, action: save)
                        .disabled(isSaving || (!isAnonymous && nickname.trimmingCharacters(in: .whitespaces).count < 2))
                }
            }
        }
    }

    private func save() {
        isSaving = true
        errorMessage = nil
        Task {
            do {
                let updated = try await Factory.repository().updateOwnProfile(
                    // Going back to anonymous lets the server regenerate the
                    // nickname: sending the real name would contradict that.
                    nickname: isAnonymous ? nil : nickname.trimmingCharacters(in: .whitespaces),
                    bio: bio.trimmingCharacters(in: .whitespaces),
                    avatarUrl: nil,
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
            // The server answers 204 even when this member had already reported
            // this target, so we always show the thank-you without revealing
            // the state of the moderation queue.
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
