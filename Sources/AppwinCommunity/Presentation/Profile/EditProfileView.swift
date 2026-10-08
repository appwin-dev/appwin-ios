import SwiftUI
import PhotosUI
import AppwinCore

/// Editing your own profile - Figma « Édition Profil » (116:8212 anonymous,
/// 116:8249 named, 178:2297 typing the name): the avatar and the name on the
/// left, the anonymity switch, the bio.
///
/// The name is edited in place behind its pen; an anonymous member shows the
/// generated name with its « Pseudo Anonyme » chip instead.
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
    @FocusState private var isEditingName: Bool

    private let bioLimit = 200

    private var trimmedNickname: String { nickname.trimmingCharacters(in: .whitespaces) }

    private var canSave: Bool {
        !isSaving && !isUploadingAvatar && (isAnonymous || trimmedNickname.count >= 2)
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
                VStack(alignment: .leading, spacing: 24) {
                    avatar
                    nameRow
                    separator
                    anonymityRow
                    separator
                    CommunityTextArea(
                        label: CommunityStrings.bio,
                        text: $bio,
                        placeholder: CommunityStrings.bioPlaceholder,
                        limit: bioLimit
                    )
                    if let errorMessage {
                        Text(errorMessage)
                            .font(theme.font(13))
                            .foregroundStyle(theme.colors.danger)
                    }
                }
                .padding(.horizontal, 20)
                .padding(.top, 16)
                .padding(.bottom, 32)
            }
        }
        .background(theme.colors.background.ignoresSafeArea())
        .onChange(of: pickerItem) { item in
            guard let item else { return }
            // The API drops the photo of an anonymous profile (anonymity
            // must be visible), so choosing one is choosing to show up.
            isAnonymous = false
            Task { await uploadAvatar(item) }
        }
        .onChange(of: isAnonymous) { anonymous in
            if anonymous {
                avatarUrl = nil
                isEditingName = false
            } else if trimmedNickname.isEmpty {
                isEditingName = true
            }
        }
        .onAppear {
            if !isAnonymous, trimmedNickname.isEmpty { isEditingName = true }
        }
    }

    // MARK: - Avatar

    /// 112pt avatar; the pen badge only when a photo can be set (not anonymous).
    private var avatar: some View {
        PhotosPicker(selection: $pickerItem, matching: .images, photoLibrary: .shared()) {
            CommunityAvatar(url: avatarUrl, nickname: displayName, size: 112)
                .overlay(alignment: .topTrailing) {
                    if !isAnonymous {
                        CommunityIconView(icon: .pen, size: 16, color: theme.colors.textPrimary)
                            .frame(width: 32, height: 32)
                            .background(theme.colors.surface, in: RoundedRectangle(cornerRadius: 12))
                            .shadow(color: .black.opacity(0.1), radius: 4, y: 4)
                    }
                }
                .overlay {
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
        .accessibilityLabel(CommunityStrings.addPhoto)
    }

    // MARK: - Name

    @ViewBuilder
    private var nameRow: some View {
        if isAnonymous {
            HStack(spacing: 8) {
                nameText(profile.nickname)
                Text(CommunityStrings.anonymousPseudo)
                    .font(theme.font(10, weight: .semibold))
                    .foregroundStyle(theme.colors.textTertiary)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 4)
                    .background(theme.colors.raised, in: RoundedRectangle(cornerRadius: 8))
            }
        } else if isEditingName || trimmedNickname.isEmpty {
            TextField("", text: $nickname, prompt: Text(CommunityStrings.nicknamePlaceholder)
                .foregroundColor(theme.colors.textTertiary))
                .focused($isEditingName)
                .textInputAutocapitalization(.words)
                .submitLabel(.done)
                .font(theme.font(24, weight: .medium))
                .foregroundStyle(theme.colors.textPrimary)
        } else {
            Button { isEditingName = true } label: {
                HStack(spacing: 8) {
                    nameText(trimmedNickname)
                    CommunityIconView(icon: .pen, size: 16, color: theme.colors.textPrimary)
                }
            }
            .buttonStyle(.plain)
            .accessibilityLabel(CommunityStrings.nickname)
        }
    }

    private func nameText(_ name: String) -> some View {
        Text(name)
            .font(theme.font(24, weight: .medium))
            .foregroundStyle(theme.colors.textPrimary)
            .lineLimit(1)
    }

    private var displayName: String {
        isAnonymous || trimmedNickname.isEmpty ? profile.nickname : trimmedNickname
    }

    // MARK: - Anonymity

    private var anonymityRow: some View {
        HStack(alignment: .top, spacing: 16) {
            VStack(alignment: .leading, spacing: 4) {
                Text(CommunityStrings.anonymous)
                    .font(theme.font(14, weight: .medium))
                    .foregroundStyle(theme.colors.textPrimary)
                Text(CommunityStrings.anonymousHint)
                    .font(theme.font(12))
                    .foregroundStyle(theme.colors.textTertiary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
            Toggle("", isOn: $isAnonymous)
                .labelsHidden()
                .tint(theme.colors.accent)
                .accessibilityLabel(CommunityStrings.anonymous)
        }
    }

    private var separator: some View {
        Rectangle().fill(theme.colors.raised).frame(height: 1)
    }

    // MARK: - Saving

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
                    nickname: isAnonymous ? nil : trimmedNickname,
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
