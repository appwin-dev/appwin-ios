import SwiftUI
import PhotosUI
import UniformTypeIdentifiers
import AVFoundation
import UIKit

/// Writing a post (text, optional photos / videos, group picker, poll).
///
/// Bottom action bar matches Support's messenger composer (Figma InputMessage):
/// image / video / poll on the left, Send on the right.
struct ComposerView: View {
    @EnvironmentObject private var session: CommunitySession
    @Environment(\.communityTheme) private var theme
    @Environment(\.dismiss) private var dismiss

    /// When set, the composer updates this post instead of creating one.
    var editingPost: CommunityPost? = nil
    let onPublished: (CommunityPost) -> Void

    @State private var body_ = ""
    @State private var groupId: String?
    @State private var isSending = false
    @State private var errorMessage: String?
    @State private var pickerItems: [PhotosPickerItem] = []
    @State private var videoPickerItems: [PhotosPickerItem] = []
    @State private var showImagePicker = false
    @State private var showVideoPicker = false
    @State private var pendingMedia: [PendingComposerMedia] = []
    @State private var isUploading = false
    @State private var showsPoll = false
    @State private var pollOptions: [String] = ["", ""]
    @State private var showsProfileEditor = false
    @FocusState private var isFocused: Bool

    private var isEditing: Bool { editingPost != nil }
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

    private static let maxVideoBytes = 75 * 1024 * 1024

    /// Groups the member may target: postable ones, plus the current group when editing.
    private var selectableGroups: [CommunityGroup] {
        var groups = session.groups.filter(\.canPost)
        if let editingPost,
           let current = session.groups.first(where: { $0.id == editingPost.groupId }),
           !groups.contains(where: { $0.id == current.id })
        {
            groups.insert(current, at: 0)
        }
        return groups
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                ScrollView {
                    VStack(alignment: .leading, spacing: theme.spacing.md) {
                        if session.profile.isAnonymous {
                            anonymousBanner
                        }

                        if selectableGroups.count > 1 {
                            groupPicker
                        }

                        TextEditor(text: $body_)
                            .focused($isFocused)
                            .font(theme.font(16))
                            .foregroundStyle(theme.colors.textPrimary)
                            .textInputAutocapitalization(.sentences)
                            .autocorrectionDisabled(false)
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

                        // Attachments sit under the draft so typing stays at the
                        // top and media / poll preview as they will on the post.
                        // Keep the row visible while the first upload is in flight
                        // (`isUploading` with an empty list), otherwise the member
                        // sees no feedback after picking a photo.
                        if !pendingMedia.isEmpty || isUploading {
                            mediaPreviews
                        }

                        if showsPoll {
                            pollEditor
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
            .navigationTitle(isEditing ? CommunityStrings.editPost : CommunityStrings.newPost)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button(CommunityStrings.cancel) { dismiss() }
                        .foregroundStyle(theme.colors.textSecondary)
                }
            }
            .onAppear {
                if let editingPost {
                    body_ = editingPost.body
                    groupId = editingPost.groupId
                    pendingMedia = editingPost.media.map {
                        PendingComposerMedia(media: $0, poster: nil)
                    }
                } else {
                    groupId = session.selectedGroupId ?? selectableGroups.first?.id
                }
                isFocused = true
            }
            .sheet(isPresented: $showsProfileEditor) {
                EditProfileView(
                    profile: session.profile,
                    leaveAnonymity: true
                ) { updated in
                    session.applyProfile(updated)
                }
                .environmentObject(session)
            }
            .photosPicker(
                isPresented: $showImagePicker,
                selection: $pickerItems,
                maxSelectionCount: max(1, maxImages - pendingMedia.count),
                matching: .images
            )
            .photosPicker(
                isPresented: $showVideoPicker,
                selection: $videoPickerItems,
                maxSelectionCount: max(1, maxImages - pendingMedia.count),
                matching: .videos
            )
            .onChange(of: pickerItems) { items in
                guard !items.isEmpty else { return }
                Task { await uploadPicked(items, asVideo: false) }
            }
            .onChange(of: videoPickerItems) { items in
                guard !items.isEmpty else { return }
                Task { await uploadPicked(items, asVideo: true) }
            }
        }
    }

    // MARK: - Anonymous CTA

    private var anonymousBanner: some View {
        VStack(alignment: .leading, spacing: theme.spacing.sm) {
            Text(CommunityStrings.composerAnonymousHint)
                .font(theme.font(13))
                .foregroundStyle(theme.colors.textSecondary)
                .fixedSize(horizontal: false, vertical: true)

            Button {
                isFocused = false
                showsProfileEditor = true
            } label: {
                Text(CommunityStrings.composerLeaveAnonymous)
                    .font(theme.font(13, weight: .semibold))
                    .foregroundStyle(theme.colors.onAccent)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 8)
                    .background(theme.composeFill, in: Capsule())
            }
            .buttonStyle(.plain)
        }
        .padding(theme.spacing.md)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            AppwinCommunityPalette.warning.opacity(0.12),
            in: RoundedRectangle(cornerRadius: theme.radius.small)
        )
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
                disabled: pendingMedia.count >= maxImages || isUploading
            ) {
                showVideoPicker = true
            }

            if !isEditing {
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
                    Text(isEditing ? CommunityStrings.save : CommunityStrings.send)
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
            .accessibilityLabel(isEditing ? CommunityStrings.save : CommunityStrings.send)
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
                ForEach(selectableGroups) { group in
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
                .textInputAutocapitalization(.sentences)
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
                        pendingThumb(item)
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
                    ZStack {
                        theme.colors.border.opacity(0.45)
                        ProgressView()
                            .tint(theme.colors.accent)
                    }
                    .frame(width: 72, height: 72)
                    .clipShape(RoundedRectangle(cornerRadius: theme.radius.small))
                    .accessibilityLabel(CommunityStrings.addPhoto)
                }
            }
        }
    }

    @ViewBuilder
    private func pendingThumb(_ item: PendingComposerMedia) -> some View {
        ZStack {
            if item.media.isVideo {
                if let poster = item.poster {
                    Image(uiImage: poster)
                        .resizable()
                        .scaledToFill()
                } else {
                    theme.colors.border.opacity(0.4)
                }
                Color.black.opacity(0.2)
                Image(systemName: "play.circle.fill")
                    .font(.system(size: 22))
                    .foregroundStyle(.white)
                    .shadow(radius: 2)
            } else {
                AsyncImage(url: item.media.url) { phase in
                    switch phase {
                    case .success(let image):
                        image.resizable().scaledToFill()
                    default:
                        theme.colors.border.opacity(0.4)
                    }
                }
            }
        }
    }

    private func uploadPicked(_ items: [PhotosPickerItem], asVideo: Bool) async {
        isUploading = true
        errorMessage = nil
        defer {
            isUploading = false
            if asVideo {
                videoPickerItems = []
            } else {
                pickerItems = []
            }
        }
        for item in items {
            guard pendingMedia.count < maxImages else { break }
            do {
                guard let data = try await item.loadTransferable(type: Data.self) else { continue }
                let utType = item.supportedContentTypes.first
                if asVideo {
                    if data.count > Self.maxVideoBytes {
                        errorMessage = CommunityStrings.videoTooLarge
                        continue
                    }
                    let (mime, ext) = Self.videoMimeAndExtension(utType: utType)
                    let poster = await Self.videoPoster(data: data, mime: mime)
                    let uploaded = try await Factory.repository().uploadMedia(
                        data: data,
                        mimeType: mime,
                        filename: "post-\(UUID().uuidString).\(ext)",
                        width: nil,
                        height: nil
                    )
                    pendingMedia.append(
                        PendingComposerMedia(
                            media: CommunityMedia(
                                url: uploaded.publicUrl,
                                width: uploaded.width,
                                height: uploaded.height,
                                alt: nil,
                                type: .video
                            ),
                            poster: poster
                        )
                    )
                } else {
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
                                alt: nil,
                                type: .image
                            ),
                            poster: nil
                        )
                    )
                }
            } catch {
                errorMessage = String(describing: error)
            }
        }
    }

    /// Map PhotosPicker UTType to the two video MIME types the API accepts.
    private static func videoMimeAndExtension(utType: UTType?) -> (String, String) {
        if let utType {
            if utType.conforms(to: .mpeg4Movie)
                || utType.preferredMIMEType == "video/mp4"
            {
                return ("video/mp4", "mp4")
            }
            if utType.conforms(to: .quickTimeMovie)
                || utType.preferredMIMEType == "video/quicktime"
            {
                return ("video/quicktime", "mov")
            }
            if let mime = utType.preferredMIMEType, mime.hasPrefix("video/") {
                let ext = utType.preferredFilenameExtension ?? "mp4"
                return (mime == "video/quicktime" ? "video/quicktime" : "video/mp4",
                        ext == "mov" ? "mov" : "mp4")
            }
        }
        return ("video/mp4", "mp4")
    }

    /// Local poster: AVAsset needs a file URL, so bytes go to a temp file first.
    private static func videoPoster(data: Data, mime: String) async -> UIImage? {
        let ext = UTType(mimeType: mime)?.preferredFilenameExtension ?? "mov"
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
            .appendingPathExtension(ext)
        guard (try? data.write(to: url)) != nil else { return nil }
        defer { try? FileManager.default.removeItem(at: url) }
        let gen = AVAssetImageGenerator(asset: AVURLAsset(url: url))
        gen.appliesPreferredTrackTransform = true
        let time = CMTime(seconds: 0.1, preferredTimescale: 600)
        guard let cg = try? await gen.image(at: time).image else { return nil }
        return UIImage(cgImage: cg)
    }

    private func submit() {
        guard canSubmit else { return }
        isSending = true
        errorMessage = nil

        Task {
            do {
                let trimmed = body_.trimmingCharacters(in: .whitespacesAndNewlines)
                let media = pendingMedia.map(\.media)
                let post: CommunityPost
                if let editingPost {
                    post = try await Factory.repository().updatePost(
                        postId: editingPost.id,
                        body: trimmed,
                        groupId: groupId,
                        media: media
                    )
                } else {
                    let trimmedPoll = pollOptions
                        .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                        .filter { !$0.isEmpty }
                    let pollPayload = showsPoll && trimmedPoll.count >= 2 ? trimmedPoll : nil
                    post = try await Factory.repository().createPost(
                        groupId: groupId,
                        body: trimmed,
                        media: media,
                        pollOptions: pollPayload
                    )
                }
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
    /// Local first-frame poster for videos; images use the public URL.
    let poster: UIImage?
}
