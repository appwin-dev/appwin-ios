//
//  MessengerComposer.swift
//  AppwinSupport
//
//  Composer: raised card, like the SaaS ConversationThread, without macros.
//

import SwiftUI
import PhotosUI
import UniformTypeIdentifiers

struct MessengerComposer: View {
    @Binding var text: String
    @State private var selectedImages: [PhotosPickerItem] = []
    @State private var selectedVideos: [PhotosPickerItem] = []
    @EnvironmentObject private var composerStore: ComposerStore
    let isSubmitting: Bool
    @FocusState.Binding var isFocused: Bool
    var isEditing: Bool = false
    var onCancelEdit: () -> Void = {}
    let onSend: () -> Void

    @Environment(\.appwinTheme) private var theme

    @State private var showImagePicker = false
    @State private var showVideoPicker = false
    @State private var showFileImporter = false
    @State private var showEmojiPicker = false

    private var isEmpty: Bool {
        text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && composerStore.pendingUploads.isEmpty
    }

    private var canSend: Bool {
        !isEmpty && !isSubmitting && !composerStore.isUploading
    }

    var body: some View {
        ZStack(alignment: .bottomLeading) {
            composerCard

            if showEmojiPicker {
                ComposerEmojiPicker { emoji in
                    text.append(emoji)
                    showEmojiPicker = false
                    isFocused = true
                }
                .background(theme.colors.background)
                .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .strokeBorder(theme.colors.border, lineWidth: 1)
                )
                .shadow(color: AppwinTokens.shadowSmooth, radius: 8, x: 0, y: 4)
                .padding(.leading, 24)
                // Sit just above the toolbar row inside the composer card.
                .padding(.bottom, 64)
                .transition(.opacity.combined(with: .scale(scale: 0.96, anchor: .bottomLeading)))
            }
        }
        .animation(.easeOut(duration: 0.15), value: showEmojiPicker)
        .photosPicker(
            isPresented: $showImagePicker,
            selection: $selectedImages,
            maxSelectionCount: 5,
            matching: .images
        )
        .photosPicker(
            isPresented: $showVideoPicker,
            selection: $selectedVideos,
            maxSelectionCount: 5,
            matching: .videos
        )
        .fileImporter(
            isPresented: $showFileImporter,
            allowedContentTypes: [.item],
            allowsMultipleSelection: true
        ) { result in
            guard let urls = try? result.get() else { return }
            for url in urls { composerStore.addFile(at: url) }
        }
        .task(id: selectedImages) {
            await ingestPhotos(selectedImages)
            selectedImages.removeAll()
        }
        .task(id: selectedVideos) {
            await ingestPhotos(selectedVideos)
            selectedVideos.removeAll()
        }
        .onChange(of: isFocused) { focused in
            if focused { showEmojiPicker = false }
        }
    }

    private var composerCard: some View {
        VStack(alignment: .leading, spacing: 0) {
            if isEditing {
                HStack(spacing: 8) {
                    SolarIcon(kind: .pen, color: theme.colors.textSecondary, size: 16)
                    Text(SupportStrings.editingBanner)
                        .font(.system(size: 12, weight: .medium))
                    Spacer(minLength: 0)
                    Button(action: onCancelEdit) {
                        SolarIcon(kind: .close, color: theme.colors.textSecondary, size: 14)
                    }
                }
                .foregroundColor(theme.colors.textSecondary)
                .padding(.horizontal, 14)
                .padding(.vertical, 10)
                .overlay(alignment: .bottom) {
                    Rectangle().fill(theme.colors.border).frame(height: 1)
                }
            }

            if !composerStore.pendingUploads.isEmpty {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        ForEach(composerStore.pendingUploads) { attachment in
                            pendingThumb(attachment)
                        }
                    }
                    .padding(.horizontal, 14)
                    .padding(.top, 12)
                }
            }

            TextField(SupportStrings.messagePlaceholder, text: $text, axis: .vertical)
                .font(.system(size: 14))
                // Forcer la couleur : en dark mode système, SwiftUI passe le
                // texte en clair alors que la carte reste claire → invisible.
                .foregroundColor(theme.colors.textPrimary)
                .tint(theme.colors.accent)
                .lineLimit(1...8)
                .focused($isFocused)
                .padding(.horizontal, 14)
                .padding(.top, 12)
                .padding(.bottom, 18)
                .frame(maxWidth: .infinity, alignment: .topLeading)
                .contentShape(Rectangle())
                .onTapGesture {
                    showEmojiPicker = false
                    isFocused = true
                }

            HStack(spacing: 4) {
                if !isEditing {
                    toolbarButton(.smileCircle, label: SupportStrings.emoji) {
                        isFocused = false
                        showEmojiPicker.toggle()
                    }

                    Rectangle()
                        .fill(theme.colors.border)
                        .frame(width: 1, height: 16)
                        .padding(.horizontal, 2)

                    toolbarButton(.gallery, label: SupportStrings.attachImage) {
                        showEmojiPicker = false
                        showImagePicker = true
                    }
                    toolbarButton(.videoLibrary, label: SupportStrings.attachVideo) {
                        showEmojiPicker = false
                        showVideoPicker = true
                    }
                    toolbarButton(.paperclip, label: SupportStrings.attachFile) {
                        showEmojiPicker = false
                        showFileImporter = true
                    }
                }

                // Gap between the icons and Send: tapping it focuses the field,
                // and its height matches the buttons'.
                Spacer(minLength: 0)
                    .frame(maxHeight: 32)
                    .contentShape(Rectangle())
                    .onTapGesture {
                        showEmojiPicker = false
                        isFocused = true
                    }

                Button(action: onSend) {
                    HStack(spacing: 4) {
                        Text(isEditing ? SupportStrings.save : SupportStrings.send)
                            .font(.system(size: 12, weight: .semibold))
                        SolarIcon(
                            kind: .plain2,
                            color: canSend ? theme.colors.onAccent : theme.colors.onAccent.opacity(0.5),
                            size: 14
                        )
                    }
                    .foregroundColor(canSend ? theme.colors.onAccent : theme.colors.onAccent.opacity(0.5))
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                    .background(
                        Capsule()
                            .fill(canSend ? theme.colors.accent : theme.colors.accent.opacity(0.4))
                    )
                }
                .disabled(!canSend)
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 6)
            .overlay(alignment: .top) {
                Rectangle().fill(theme.colors.border).frame(height: 1)
            }
        }
        .background(theme.colors.background)
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .strokeBorder(theme.colors.border, lineWidth: 1)
        )
        // Carte claire (tokens light) : empêche le TextField système de
        // basculer en texte blanc quand l'app hôte est en dark mode.
        .environment(\.colorScheme, .light)
        .shadow(color: AppwinTokens.shadowSmooth, radius: 2, x: 0, y: 4)
        .padding(.horizontal, 16)
        .padding(.bottom, 16)
        .padding(.top, 8)
    }

    private func toolbarButton(
        _ kind: SolarIcon.Kind,
        label: String,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            SolarIcon(kind: kind, color: theme.colors.textTertiary, size: 16)
                .frame(width: 32, height: 32)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(label)
    }

    private func ingestPhotos(_ items: [PhotosPickerItem]) async {
        for item in items {
            guard let data = try? await item.loadTransferable(type: Data.self) else { continue }
            composerStore.addMedia(data: data, utType: item.supportedContentTypes.first)
        }
    }

    private func pendingThumb(_ attachment: PickedAttachment) -> some View {
        ComposerAttachmentThumbnail(attachment: attachment)
            .frame(width: 64, height: 64)
            .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
            .overlay {
                let p = composerStore.progress(for: attachment.id)
                if p < 1 {
                    ZStack {
                        Color.black.opacity(0.35)
                        Circle()
                            .trim(from: 0, to: p)
                            .stroke(Color.white, style: StrokeStyle(lineWidth: 3, lineCap: .round))
                            .rotationEffect(.degrees(-90))
                            .frame(width: 26, height: 26)
                            .animation(.easeInOut, value: p)
                    }
                }
            }
            .overlay(alignment: .topTrailing) {
                Button {
                    composerStore.remove(id: attachment.id)
                } label: {
                    SolarIcon(kind: .closeCircle, color: .white, size: 18)
                        .background(Circle().fill(Color.black.opacity(0.55)))
                }
                .offset(x: 4, y: -4)
            }
    }
}
