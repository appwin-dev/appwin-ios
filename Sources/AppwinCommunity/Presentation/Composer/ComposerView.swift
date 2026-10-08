import SwiftUI
import PhotosUI
import UniformTypeIdentifiers
import AVFoundation
import UIKit

/// Writing a post (text, optional photos / videos, group picker, poll).
///
/// Figma create-post (19:4560, 19:4713, 19:4974): "Annuler" and the title on
/// the page, attachments and poll above the text, and the tool row with the
/// brand "Publier" pill over the keyboard.
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
    @State private var bannerDismissed = false
    /// The classifier removed the post as it was written: say so rather than show it.
    @State private var showsRemovedAlert = false
    @FocusState private var isFocused: Bool

    private var isEditing: Bool { editingPost != nil }
    private var limit: Int { session.config.limits.postMaxLength }
    private var maxImages: Int { session.config.limits.maxImagesPerPost }
    private var imagesEnabled: Bool { session.config.features.imagesEnabled && session.allows(\.images) }
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
                CommunityNavHeader(
                    leadingTitle: CommunityStrings.cancel,
                    onLeading: { dismiss() },
                    title: isEditing ? CommunityStrings.editPost : CommunityStrings.newPost
                )

                ScrollView {
                    VStack(alignment: .leading, spacing: 24) {
                        if session.profile.isAnonymous, !bannerDismissed {
                            anonymousBanner
                        }

                        if selectableGroups.count > 1 {
                            groupPicker
                        }

                        if showsPoll {
                            pollEditor
                        }

                        // Attachments sit above the draft, as in Figma. Keep the
                        // row visible while the first upload is in flight
                        // (`isUploading` with an empty list), otherwise the member
                        // sees no feedback after picking a photo.
                        if !pendingMedia.isEmpty || isUploading {
                            mediaPreviews
                        }

                        TextEditor(text: $body_)
                            .focused($isFocused)
                            .font(theme.font(16))
                            .foregroundStyle(theme.colors.textPrimary)
                            .tint(theme.colors.textSecondary)
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

                        if let errorMessage {
                            Text(errorMessage)
                                .font(theme.font(13))
                                .foregroundStyle(theme.colors.danger)
                        }
                    }
                    .padding(.horizontal, 16)
                }

                composerActionBar
            }
            .background(theme.colors.background)
            .toolbar(.hidden, for: .navigationBar)
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
            .alert(CommunityStrings.postRemovedAlertTitle, isPresented: $showsRemovedAlert) {
                Button(CommunityStrings.understood) {
                    // The bell now has a card explaining why.
                    Task { await session.bootstrap() }
                    dismiss()
                }
            } message: {
                Text(CommunityStrings.postRemovedAlertMessage)
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

    /// Figma 19:4560: who the post will show, a shortcut to the profile, a close.
    private var anonymousBanner: some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 0) {
                Text(CommunityStrings.anonymousBannerTitle)
                Text("@\(session.profile.nickname)")
            }
            .font(theme.font(12))
            .foregroundStyle(theme.colors.textSecondary)
            .frame(maxWidth: .infinity, alignment: .leading)

            Button {
                isFocused = false
                CommunityProfileEditing.begin { showsProfileEditor = true }
            } label: {
                Text(CommunityStrings.editProfileShort)
                    .font(theme.font(12, weight: .semibold))
                    .foregroundStyle(theme.colors.textPrimary)
                    .padding(.horizontal, 12)
                    .padding(.top, 8)
                    .padding(.bottom, 7)
                    .background(theme.colors.surface, in: RoundedRectangle(cornerRadius: 12))
            }
            .buttonStyle(.plain)

            Button {
                withAnimation(.easeOut(duration: 0.15)) { bannerDismissed = true }
            } label: {
                CommunityIconView(icon: .close, size: 16, color: theme.colors.textPrimary)
                    .frame(width: 24, height: 24)
            }
            .buttonStyle(.plain)
            .accessibilityLabel(CommunityStrings.dismiss)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .background(theme.colors.raised, in: RoundedRectangle(cornerRadius: 16))
    }

    // MARK: - Action bar (Figma InputMessage footer)

    private var composerActionBar: some View {
        HStack(spacing: 8) {
            if imagesEnabled {
                toolButton(
                    icon: .gallery,
                    label: CommunityStrings.addPhoto,
                    disabled: pendingMedia.count >= maxImages || isUploading
                ) {
                    showImagePicker = true
                }
            }

            if session.allows(\.videos) {
                toolButton(
                    icon: .videocamera,
                    label: CommunityStrings.addVideo,
                    disabled: pendingMedia.count >= maxImages || isUploading
                ) {
                    showVideoPicker = true
                }
            }

            if !isEditing, session.allows(\.polls) {
                toolButton(
                    icon: .chart,
                    activeIcon: .chartBold,
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
            }

            CommunityBrandPill(
                title: isEditing ? CommunityStrings.save : CommunityStrings.publish,
                icon: .plain,
                isEnabled: canSubmit,
                isLoading: isSending,
                action: submit
            )
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 12)
        .background(theme.colors.background)
    }

    /// Figma tool icon (19:5129): bg/low square; when active, outlined in
    /// text/main with the Bold glyph in text/main.
    private func toolButton(
        icon: CommunityIcon,
        activeIcon: CommunityIcon? = nil,
        label: String,
        disabled: Bool,
        active: Bool = false,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            CommunityIconView(
                icon: active ? (activeIcon ?? icon) : icon,
                size: 16,
                color: active ? theme.colors.textPrimary : theme.colors.textTertiary.opacity(disabled ? 0.4 : 1)
            )
                .frame(width: 32, height: 32)
                .background(theme.colors.raised, in: RoundedRectangle(cornerRadius: theme.radius.field))
                .overlay {
                    if active {
                        RoundedRectangle(cornerRadius: theme.radius.field)
                            .strokeBorder(theme.colors.textPrimary, lineWidth: 1)
                    }
                }
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
                                    RoundedRectangle(cornerRadius: theme.radius.card).fill(theme.accentFill)
                                } else {
                                    RoundedRectangle(cornerRadius: theme.radius.card)
                                        .strokeBorder(theme.colors.border, lineWidth: 1)
                                }
                            }
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    /// Figma sondage (19:5111): white option fields, then a dashed "add" row.
    private var pollEditor: some View {
        VStack(alignment: .leading, spacing: 4) {
            ForEach(pollOptions.indices, id: \.self) { index in
                TextField(
                    "\(CommunityStrings.pollOptionPlaceholder) \(index + 1)",
                    text: $pollOptions[index]
                )
                .font(theme.font(14, weight: .medium))
                .foregroundStyle(theme.colors.textPrimary)
                .textInputAutocapitalization(.sentences)
                .padding(.horizontal, 16)
                .padding(.vertical, 12)
                .background(theme.colors.surface, in: RoundedRectangle(cornerRadius: theme.radius.field))
            }
            if pollOptions.count < 6 {
                Button {
                    pollOptions.append("")
                } label: {
                    HStack(spacing: 8) {
                        Image(systemName: "plus")
                            .font(.system(size: 13, weight: .medium))
                        Text(CommunityStrings.addPollOption)
                            .font(theme.font(14, weight: .medium))
                        Spacer(minLength: 0)
                    }
                    .foregroundStyle(theme.colors.textTertiary)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 12)
                    .overlay(
                        RoundedRectangle(cornerRadius: theme.radius.field)
                            .strokeBorder(theme.colors.border, style: StrokeStyle(lineWidth: 1, dash: [4, 3]))
                    )
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
        }
    }

    private var mediaPreviews: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(pendingMedia) { item in
                    // The remove button sits inside the thumbnail: offset past
                    // its edge, the horizontal ScrollView clipped it.
                    ZStack(alignment: .topTrailing) {
                        pendingThumb(item)
                            .frame(width: 72, height: 72)
                            .clipShape(RoundedRectangle(cornerRadius: theme.radius.small))

                        Button {
                            pendingMedia.removeAll { $0.id == item.id }
                        } label: {
                            Image(systemName: "xmark.circle.fill")
                                .font(.system(size: 20))
                                .foregroundStyle(.white, .black.opacity(0.55))
                        }
                        .buttonStyle(.plain)
                        .padding(4)
                    }
                }
                if isUploading {
                    ZStack {
                        theme.colors.raised
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
                    theme.colors.raised
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
                        theme.colors.raised
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
        if !asVideo {
            await uploadImages(Array(items.prefix(max(0, maxImages - pendingMedia.count))))
            return
        }
        for item in items {
            guard pendingMedia.count < maxImages else { break }
            do {
                guard let data = try await item.loadTransferable(type: Data.self) else { continue }
                let utType = item.supportedContentTypes.first
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
            } catch {
                errorMessage = String(describing: error)
            }
        }
    }

    /// Photos go up in parallel, then land in the order they were picked: one
    /// after the other, four photos stacked four full round trips.
    private func uploadImages(_ items: [PhotosPickerItem]) async {
        let results = await withTaskGroup(of: (Int, Result<CommunityMedia, Error>?).self) { group in
            for (index, item) in items.enumerated() {
                group.addTask {
                    do {
                        guard let data = try await item.loadTransferable(type: Data.self) else {
                            return (index, nil)
                        }
                        let media = try await Factory.repository().uploadImage(data, filenamePrefix: "post")
                        return (index, .success(media))
                    } catch {
                        return (index, .failure(error))
                    }
                }
            }
            var collected: [(Int, Result<CommunityMedia, Error>?)] = []
            for await result in group { collected.append(result) }
            return collected.sorted { $0.0 < $1.0 }.compactMap(\.1)
        }
        for result in results {
            switch result {
            case .success(let media):
                pendingMedia.append(PendingComposerMedia(media: media, poster: nil))
            case .failure(let error):
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
                if post.isRemoved {
                    showsRemovedAlert = true
                } else {
                    onPublished(post)
                    dismiss()
                }
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
