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
                .font(.system(size: 14, weight: .medium))
                .foregroundColor(theme.colors.textPrimary)
                .tint(theme.colors.accent)
                .lineLimit(1...8)
                .focused($isFocused)
                .padding(16)
                .frame(maxWidth: .infinity, alignment: .topLeading)
                .contentShape(Rectangle())
                .onTapGesture {
                    showEmojiPicker = false
                    isFocused = true
                }

            // Figma input/messageSupport footer: 20pt icons 16 apart, then the
            // square gradient send button.
            HStack(spacing: 8) {
                if !isEditing {
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
                    toolbarButton(.smileCircle, label: SupportStrings.emoji) {
                        isFocused = false
                        showEmojiPicker.toggle()
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
                    SolarIcon(kind: .arrowUp, color: theme.colors.onAccent, size: 16)
                        .frame(width: 32, height: 32)
                        .background(
                            RoundedRectangle(cornerRadius: theme.radius.card, style: .continuous)
                                .fill(theme.accentFill(autoGradient: theme.design.autoGradient))
                        )
                        .overlay(
                            RoundedRectangle(cornerRadius: theme.radius.card, style: .continuous)
                                .strokeBorder(Color.white.opacity(0.1), lineWidth: 2)
                        )
                        .opacity(canSend ? 1 : 0.4)
                }
                .disabled(!canSend)
                .accessibilityLabel(isEditing ? SupportStrings.save : SupportStrings.send)
            }
            .padding(.leading, 12)
            .padding(.trailing, 8)
            .padding(.bottom, 8)
        }
        // Figma input/messageSupport: bg/container, border/low, shadow/low.
        .background(theme.colors.background)
        .clipShape(RoundedRectangle(cornerRadius: theme.radius.card, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: theme.radius.card, style: .continuous)
                .strokeBorder(AppwinTokens.surfaceMuted, lineWidth: 1)
        )
        .shadow(color: AppwinTokens.shadowLow, radius: 20, x: 0, y: 16)
        .padding(.horizontal, 20)
        .padding(.bottom, 16)
        .padding(.top, 8)
    }

    private func toolbarButton(
        _ kind: SolarIcon.Kind,
        label: String,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            SolarIcon(kind: kind, color: theme.colors.textTertiary, size: 20)
                .frame(width: 28, height: 32)
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
