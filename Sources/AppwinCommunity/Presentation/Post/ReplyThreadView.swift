import SwiftUI
import PhotosUI
import UIKit

/// Dedicated replies screen for a root comment (Figma "Réponses").
/// Opened from "→ See N replies" when the thread is collapsed on the post.
struct ReplyThreadView: View {
    @EnvironmentObject private var session: CommunitySession
    @Environment(\.communityTheme) private var theme

    let rootCommentId: String
    @ObservedObject var comments: CommentStore
    let onCommentCountChange: (Int) -> Void
    /// When false, do not pop the keyboard on appear (default: open to read).
    var focusComposerOnAppear: Bool = false
    /// When true (push deeplink), scroll to the latest reply once the thread is laid out.
    var scrollToLatestOnAppear: Bool = false

    @State private var draft = ""
    @State private var pendingMedia: [CommunityMedia] = []
    @State private var pickerItem: PhotosPickerItem?
    @State private var isUploading = false
    @State private var reportTarget: ReportTarget?
    @State private var selectedProfileId: String?
    @State private var scrollToBottomTick = 0
    @State private var didScrollOnAppear = false
    @FocusState private var isComposerFocused: Bool

    private var maxImages: Int { session.config.limits.maxImagesPerPost }
    private var imagesEnabled: Bool { session.config.features.imagesEnabled }

    private var root: CommunityComment? {
        comments.comments.first { $0.id == rootCommentId }
    }

    var body: some View {
        VStack(spacing: 0) {
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: theme.spacing.md) {
                        if let root {
                            CommentRow(
                                comment: root,
                                depth: 0,
                                canReact: session.config.features.reactionsEnabled,
                                canReply: session.config.features.repliesEnabled,
                                showTranslation: session.config.features.translationEnabled,
                                availableReactions: session.config.features.reactions,
                                embedReplies: false,
                                useBubbleStyle: true,
                                onReact: { target, kind in
                                    Task { await comments.toggleReaction(commentId: target.id, kind: kind) }
                                },
                                onReply: { target in
                                    comments.replyingTo = target
                                    isComposerFocused = true
                                },
                                onDelete: { target in
                                    Task {
                                        await comments.delete(commentId: target.id)
                                        onCommentCountChange(-1)
                                    }
                                },
                                onReport: { target in
                                    reportTarget = ReportTarget(type: "comment", id: target.id)
                                },
                                onOpenProfile: session.config.features.profilesEnabled
                                    ? { target in
                                        guard let author = target.author, author.isAddressable else { return }
                                        selectedProfileId = author.id
                                    }
                                    : nil
                            )

                            ForEach(root.replies) { reply in
                                CommentRow(
                                    comment: reply,
                                    depth: 1,
                                    canReact: session.config.features.reactionsEnabled,
                                    canReply: session.config.features.repliesEnabled,
                                    showTranslation: session.config.features.translationEnabled,
                                    availableReactions: session.config.features.reactions,
                                    embedReplies: false,
                                    useBubbleStyle: true,
                                    onReact: { target, kind in
                                        Task { await comments.toggleReaction(commentId: target.id, kind: kind) }
                                    },
                                    onReply: { target in
                                        comments.replyingTo = target
                                        isComposerFocused = true
                                    },
                                    onDelete: { target in
                                        Task {
                                            await comments.delete(commentId: target.id)
                                            onCommentCountChange(-1)
                                        }
                                    },
                                    onReport: { target in
                                        reportTarget = ReportTarget(type: "comment", id: target.id)
                                    },
                                    onOpenProfile: session.config.features.profilesEnabled
                                        ? { target in
                                            guard let author = target.author, author.isAddressable else { return }
                                            selectedProfileId = author.id
                                        }
                                        : nil
                                )
                                .id(reply.id)
                                .padding(.leading, theme.spacing.xl)
                            }
                        }

                        Color.clear
                            // Extra room so the last reply clears the composer.
                            .frame(height: 24)
                            .id("replies-bottom")
                    }
                    .padding(theme.spacing.md)
                }
                .scrollDismissesKeyboard(.interactively)
                .simultaneousGesture(
                    TapGesture().onEnded { dismissComposerKeyboard() }
                )
                .onChange(of: scrollToBottomTick) { _ in
                    withAnimation(.easeOut(duration: 0.25)) {
                        proxy.scrollTo("replies-bottom", anchor: .bottom)
                    }
                }
            }

            if session.config.features.commentsEnabled, !session.profile.isBanned {
                composer
            }
        }
        .background(theme.colors.background)
        .navigationTitle(CommunityStrings.replies)
        .navigationBarTitleDisplayMode(.inline)
        .sheet(item: $reportTarget) { target in
            ReportSheet(target: target).environmentObject(session)
        }
        .sheet(item: Binding(
            get: { selectedProfileId.map(ProfileTarget.init) },
            set: { selectedProfileId = $0?.id }
        )) { target in
            ProfileView(profileId: target.id, onCompose: {})
                .environmentObject(session)
        }
        .onAppear {
            if comments.replyingTo == nil, let root {
                comments.replyingTo = root
            }
            if focusComposerOnAppear {
                isComposerFocused = true
            }
            scheduleScrollToLatestIfNeeded()
        }
        .onChange(of: comments.comments.count) { _ in
            scheduleScrollToLatestIfNeeded()
        }
        .onChange(of: pickerItem) { item in
            guard let item else { return }
            Task { await uploadPicked(item) }
        }
    }

    private func scheduleScrollToLatestIfNeeded() {
        guard scrollToLatestOnAppear, !didScrollOnAppear else { return }
        guard root != nil else { return }
        didScrollOnAppear = true
        Task { @MainActor in
            // Wait for LazyVStack to measure the reply rows.
            try? await Task.sleep(nanoseconds: 100_000_000)
            scrollToBottomTick += 1
            try? await Task.sleep(nanoseconds: 150_000_000)
            scrollToBottomTick += 1
        }
    }

    private var composer: some View {
        VStack(spacing: 0) {
            Divider().overlay(theme.colors.border)

            if let replyingTo = comments.replyingTo, replyingTo.id != rootCommentId {
                HStack {
                    Text(String(
                        format: CommunityStrings.replyingTo,
                        replyingTo.author?.nickname ?? ""
                    ))
                    .font(theme.font(12))
                    .foregroundStyle(theme.colors.textTertiary)
                    Spacer()
                    Button {
                        comments.replyingTo = root
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundStyle(theme.colors.textTertiary)
                    }
                    .buttonStyle(.plain)
                }
                .padding(.horizontal, theme.spacing.md)
                .padding(.top, theme.spacing.sm)
            }

            if !pendingMedia.isEmpty || isUploading {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        ForEach(Array(pendingMedia.enumerated()), id: \.offset) { index, item in
                            ZStack(alignment: .topTrailing) {
                                AsyncImage(url: item.url) { phase in
                                    switch phase {
                                    case .success(let image):
                                        image.resizable().scaledToFill()
                                    default:
                                        theme.colors.border.opacity(0.4)
                                    }
                                }
                                .frame(width: 56, height: 56)
                                .clipShape(RoundedRectangle(cornerRadius: theme.radius.small))

                                Button {
                                    pendingMedia.remove(at: index)
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
                            .frame(width: 56, height: 56)
                            .clipShape(RoundedRectangle(cornerRadius: theme.radius.small))
                        }
                    }
                    .padding(.horizontal, theme.spacing.md)
                }
                .padding(.top, theme.spacing.sm)
            }

            HStack(spacing: theme.spacing.sm) {
                if imagesEnabled {
                    PhotosPicker(selection: $pickerItem, matching: .images) {
                        Image(systemName: "photo")
                            .font(.system(size: 18, weight: .medium))
                            .foregroundStyle(
                                pendingMedia.count >= maxImages || isUploading
                                    ? theme.colors.textTertiary.opacity(0.5)
                                    : theme.colors.textTertiary
                            )
                            .frame(width: 32, height: 32)
                    }
                    .disabled(pendingMedia.count >= maxImages || isUploading)
                    .accessibilityLabel(CommunityStrings.addPhoto)
                }

                TextField(CommunityStrings.replyToComment, text: $draft, axis: .vertical)
                    .focused($isComposerFocused)
                    .font(theme.font(14))
                    .lineLimit(1...4)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                    .background(
                        theme.colors.surface,
                        in: RoundedRectangle(cornerRadius: theme.radius.field)
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: theme.radius.field)
                            .stroke(theme.colors.border, lineWidth: 1)
                    )

                Button { send() } label: {
                    Image(systemName: "arrow.up.circle.fill")
                        .font(.system(size: 28))
                        .foregroundStyle(canSend ? theme.colors.accent : theme.colors.textTertiary)
                }
                .buttonStyle(.plain)
                .disabled(!canSend)
            }
            .padding(theme.spacing.md)
        }
        .background(theme.colors.background)
    }

    private var canSend: Bool {
        let hasText = !draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        return (hasText || !pendingMedia.isEmpty) && !comments.isSending && !isUploading
    }

    private func dismissComposerKeyboard() {
        isComposerFocused = false
        UIApplication.shared.sendAction(
            #selector(UIResponder.resignFirstResponder),
            to: nil,
            from: nil,
            for: nil
        )
    }

    private func send() {
        let text = draft
        let media = pendingMedia
        // Keep the thread rooted: if the member cleared the banner, still reply
        // to the root rather than posting a top-level comment on the post.
        if comments.replyingTo == nil {
            comments.replyingTo = root
        }
        dismissComposerKeyboard()
        Task {
            let ok = await comments.send(body: text, media: media)
            if ok {
                draft = ""
                pendingMedia = []
                onCommentCountChange(1)
                comments.replyingTo = root
                try? await Task.sleep(nanoseconds: 100_000_000)
                scrollToBottomTick += 1
                try? await Task.sleep(nanoseconds: 150_000_000)
                scrollToBottomTick += 1
            }
        }
    }

    private func uploadPicked(_ item: PhotosPickerItem) async {
        guard pendingMedia.count < maxImages else { return }
        isUploading = true
        defer {
            isUploading = false
            pickerItem = nil
        }
        do {
            guard let data = try await item.loadTransferable(type: Data.self) else { return }
            let uploaded = try await Factory.repository().uploadMedia(
                data: data,
                mimeType: "image/jpeg",
                filename: "comment-\(UUID().uuidString).jpg",
                width: nil,
                height: nil
            )
            pendingMedia.append(
                CommunityMedia(
                    url: uploaded.publicUrl,
                    width: uploaded.width,
                    height: uploaded.height,
                    alt: nil,
                    type: .image
                )
            )
        } catch {}
    }
}

/// Navigation value for pushing the replies screen from post detail.
struct ReplyThreadNav: Hashable, Identifiable {
    let id: String
}
