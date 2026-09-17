import SwiftUI
import PhotosUI
import UniformTypeIdentifiers

/// Writing a post (text, optional photos, group picker, poll).
///
/// Bottom action bar matches Support's messenger composer (Figma InputMessage):
/// image / video / poll on the left, Send on the right.
struct ComposerView: View {
    @EnvironmentObject private var session: CommunitySession
    @Environment(\.communityTheme) private var theme
    @Environment(\.dismiss) private var dismiss

    let onPublished: (CommunityPost) -> Void

    @State private var body_ = ""
    @State private var groupId: String?
    @State private var isSending = false
    @State private var errorMessage: String?
    @State private var pickerItems: [PhotosPickerItem] = []
    @State private var showImagePicker = false
    @State private var pendingMedia: [PendingComposerMedia] = []
    @State private var isUploading = false
    @State private var showsPoll = false
    @State private var pollOptions: [String] = ["", ""]
    @State private var showsVideoSoon = false
    @FocusState private var isFocused: Bool

    private var limit: Int { session.config.limits.postMaxLength }
    private var maxImages: Int { session.config.limits.maxImagesPerPost }
    private var imagesEnabled: Bool { session.config.features.imagesEnabled }
    private var remaining: Int { limit - body_.count }
    /// Counter threshold: the last fifth of the limit.
    private var showsCounter: Bool { remaining <= limit / 5 }
    private var canSubmit: Bool {
        !body_.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && remaining >= 0
            && !isSending
            && !isUploading
    }

    /// Groups the member is allowed to post in.
    private var postableGroups: [CommunityGroup] {
        session.groups.filter(\.canPost)
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                ScrollView {
                    VStack(alignment: .leading, spacing: theme.spacing.md) {
                        if postableGroups.count > 1 {
                            groupPicker
                        }

                        if !pendingMedia.isEmpty {
                            mediaPreviews
                        }

                        if showsPoll {
                            pollEditor
                        }

                        TextEditor(text: $body_)
                            .focused($isFocused)
                            .font(theme.font(16))
                            .foregroundStyle(theme.colors.textPrimary)
                            .scrollContentBackground(.hidden)
                            .frame(minHeight: 160)
                            .overlay(alignment: .topLeading) {
                                if body_.isEmpty {
                                    Text(CommunityStrings.composerPlaceholder)
                                        .font(theme.font(16))
                                        .foregroundStyle(theme.colors.textTertiary)
                                        .padding(.top, 8)
                                        .padding(.leading, 5)
                                        .allowsHitTesting(false)
                                }
                            }

                        if let errorMessage {
                            Text(errorMessage)
                                .font(theme.font(13))
                                .foregroundStyle(theme.colors.danger)
                        }
                    }
                    .padding(theme.spacing.lg)
                }

                composerActionBar
            }
            .background(theme.colors.background)
            .navigationTitle(CommunityStrings.newPost)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button(CommunityStrings.cancel) { dismiss() }
                        .foregroundStyle(theme.colors.textSecondary)
                }
            }
            .onAppear {
                groupId = session.selectedGroupId ?? postableGroups.first?.id
                isFocused = true
            }
            .photosPicker(
                isPresented: $showImagePicker,
                selection: $pickerItems,
                maxSelectionCount: max(1, maxImages - pendingMedia.count),
                matching: .images
            )
            .onChange(of: pickerItems) { items in
                guard !items.isEmpty else { return }
                Task { await uploadPicked(items) }
            }
            .alert(
                CommunityStrings.addVideo,
                isPresented: $showsVideoSoon
            ) {
                Button(CommunityStrings.cancel, role: .cancel) {}
            } message: {
                Text(CommunityStrings.videoComingSoon)
            }
        }
    }

    // MARK: - Action bar (Figma InputMessage footer)

    private var composerActionBar: some View {
        HStack(spacing: 4) {
            if imagesEnabled {
                actionButton(
                    systemImage: "photo",
                    label: CommunityStrings.addPhoto,
                    disabled: pendingMedia.count >= maxImages || isUploading
                ) {
                    showImagePicker = true
                }
            }

            actionButton(
                systemImage: "video",
                label: CommunityStrings.addVideo,
                disabled: false
            ) {
                showsVideoSoon = true
            }

            actionButton(
                systemImage: "chart.bar",
                label: CommunityStrings.addPoll,
                disabled: false,
                active: showsPoll
            ) {
                showsPoll.toggle()
                if showsPoll, pollOptions.count < 2 {
                    pollOptions = ["", ""]
                }
            }

            Spacer(minLength: 0)

            if showsCounter {
                Text("\(remaining)")
                    .font(theme.font(13, weight: .medium))
                    .foregroundStyle(
                        remaining < 0 ? theme.colors.danger : theme.colors.textTertiary
                    )
                    .padding(.trailing, 4)
            }

            Button(action: submit) {
                HStack(spacing: 4) {
                    Image(systemName: "paperplane.fill")
                        .font(.system(size: 12, weight: .semibold))
                    Text(CommunityStrings.send)
                        .font(theme.font(14, weight: .semibold))
                }
                .foregroundStyle(
                    canSubmit
                        ? theme.colors.onAccent
                        : theme.colors.onAccent.opacity(0.5)
                )
                .padding(.horizontal, 12)
                .padding(.vertical, 10)
                .background {
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .fill(canSubmit ? theme.composeFill : AnyShapeStyle(theme.colors.accent.opacity(0.4)))
                }
                .shadow(
                    color: canSubmit ? theme.accentShadow : .clear,
                    radius: 4,
                    y: 4
                )
            }
            .buttonStyle(.plain)
            .disabled(!canSubmit)
            .accessibilityLabel(CommunityStrings.send)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 8)
        .background(theme.colors.background)
        .overlay(alignment: .top) {
            Rectangle()
                .fill(theme.colors.border)
                .frame(height: 1)
        }
    }

    private func actionButton(
        systemImage: String,
        label: String,
        disabled: Bool,
        active: Bool = false,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            Image(systemName: systemImage)
                .font(.system(size: 16, weight: .medium))
                .foregroundStyle(
                    disabled
                        ? theme.colors.textTertiary.opacity(0.5)
                        : active
                            ? theme.colors.accent
                            : theme.colors.textTertiary
                )
                .frame(width: 32, height: 32)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(disabled)
        .accessibilityLabel(label)
    }

    private var groupPicker: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: theme.spacing.sm) {
                ForEach(postableGroups) { group in
                    Button {
                        groupId = group.id
                    } label: {
                        Text([group.emoji, group.name].compactMap { $0 }.joined(separator: " "))
                            .font(theme.font(13, weight: groupId == group.id ? .semibold : .medium))
                            .foregroundStyle(
                                groupId == group.id
                                    ? theme.colors.onAccent
                                    : theme.colors.textSecondary
                            )
                            .padding(.horizontal, 12)
                            .padding(.vertical, 7)
                            .background {
                                if groupId == group.id {
                                    Capsule().fill(theme.accentFill)
                                } else {
                                    Capsule().fill(theme.colors.surface)
                                }
                            }
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    private var pollEditor: some View {
        VStack(alignment: .leading, spacing: 8) {
            ForEach(pollOptions.indices, id: \.self) { index in
                TextField(
                    "\(CommunityStrings.pollOptionPlaceholder) \(index + 1)",
                    text: $pollOptions[index]
                )
                .padding(10)
                .background(theme.colors.surface, in: RoundedRectangle(cornerRadius: theme.radius.small))
            }
            if pollOptions.count < 6 {
                Button(CommunityStrings.addPollOption) {
                    pollOptions.append("")
                }
                .font(theme.font(13, weight: .medium))
                .foregroundStyle(theme.colors.accent)
                .buttonStyle(.plain)
            }
        }
    }

    private var mediaPreviews: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(pendingMedia) { item in
                    ZStack(alignment: .topTrailing) {
                        AsyncImage(url: item.media.url) { phase in
                            switch phase {
                            case .success(let image):
                                image.resizable().scaledToFill()
                            default:
                                theme.colors.border.opacity(0.4)
                            }
                        }
                        .frame(width: 72, height: 72)
                        .clipShape(RoundedRectangle(cornerRadius: theme.radius.small))

                        Button {
                            pendingMedia.removeAll { $0.id == item.id }
                        } label: {
                            Image(systemName: "xmark.circle.fill")
                                .foregroundStyle(.white, .black.opacity(0.55))
                        }
                        .offset(x: 4, y: -4)
                    }
                }
                if isUploading {
                    ProgressView()
                        .frame(width: 72, height: 72)
                }
            }
        }
    }

    private func uploadPicked(_ items: [PhotosPickerItem]) async {
        isUploading = true
        errorMessage = nil
        defer {
            isUploading = false
            pickerItems = []
        }
        for item in items {
            guard pendingMedia.count < maxImages else { break }
            do {
                guard let data = try await item.loadTransferable(type: Data.self) else { continue }
                let uploaded = try await Factory.repository().uploadMedia(
                    data: data,
                    mimeType: "image/jpeg",
                    filename: "post-\(UUID().uuidString).jpg",
                    width: nil,
                    height: nil
                )
                pendingMedia.append(
                    PendingComposerMedia(
                        media: CommunityMedia(
                            url: uploaded.publicUrl,
                            width: uploaded.width,
                            height: uploaded.height,
                            alt: nil
                        )
                    )
                )
            } catch {
                errorMessage = String(describing: error)
            }
        }
    }

    private func submit() {
        guard canSubmit else { return }
        isSending = true
        errorMessage = nil

        Task {
            do {
                let trimmedPoll = pollOptions
                    .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                    .filter { !$0.isEmpty }
                let pollPayload = showsPoll && trimmedPoll.count >= 2 ? trimmedPoll : nil
                let post = try await Factory.repository().createPost(
                    groupId: groupId,
                    body: body_.trimmingCharacters(in: .whitespacesAndNewlines),
                    media: pendingMedia.map(\.media),
                    pollOptions: pollPayload
                )
                onPublished(post)
                dismiss()
            } catch {
                errorMessage = String(describing: error)
            }
            isSending = false
        }
    }
}

private struct PendingComposerMedia: Identifiable {
    let id = UUID()
    let media: CommunityMedia
}
