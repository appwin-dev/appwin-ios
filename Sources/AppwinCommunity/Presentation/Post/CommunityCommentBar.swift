import SwiftUI
import PhotosUI

/// Bottom bar of the comments and replies screens - Figma interaction-footer
/// (19:5444): the member's avatar, a bg/low field, the square accent send.
///
/// The photo picker sits inside the field: Figma leaves it out, but comments
/// accept images and the bar is the only place to attach one.
struct CommunityCommentBar: View {
    @EnvironmentObject private var session: CommunitySession
    @Environment(\.communityTheme) private var theme

    @Binding var draft: String
    var isFocused: FocusState<Bool>.Binding
    let placeholder: String
    /// "Replying to X", with the action that clears it.
    var replyingToLabel: String?
    var onClearReplyingTo: (() -> Void)?
    @Binding var pendingMedia: [CommunityMedia]
    @Binding var pickerItem: PhotosPickerItem?
    let isUploading: Bool
    let canSend: Bool
    let onSend: () -> Void

    private var maxImages: Int { session.config.limits.maxImagesPerPost }
    private var imagesEnabled: Bool { session.config.features.imagesEnabled }
    private var canAttach: Bool { pendingMedia.count < maxImages && !isUploading }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            if let replyingToLabel {
                HStack {
                    Text(replyingToLabel)
                        .font(theme.font(12, weight: .medium))
                        .foregroundStyle(theme.colors.textTertiary)
                    Spacer()
                    if let onClearReplyingTo {
                        Button(action: onClearReplyingTo) {
                            Image(systemName: "xmark.circle.fill")
                                .foregroundStyle(theme.colors.textTertiary)
                        }
                        .buttonStyle(.plain)
                    }
                }
            }

            if !pendingMedia.isEmpty || isUploading {
                attachments
            }

            HStack(spacing: 4) {
                CommunityAvatar(
                    url: session.profile.avatarUrl,
                    nickname: session.profile.nickname,
                    size: 32
                )
                .padding(.trailing, 4)

                field

                Button(action: onSend) {
                    CommunityIconView(icon: .arrowUp, size: 16, color: theme.colors.onAccent)
                        .frame(width: 38, height: 38)
                        .background(theme.composeFill, in: RoundedRectangle(cornerRadius: theme.radius.card))
                        .overlay(
                            RoundedRectangle(cornerRadius: theme.radius.card)
                                .strokeBorder(.white.opacity(0.1), lineWidth: 2)
                        )
                        .opacity(canSend ? 1 : 0.5)
                }
                .buttonStyle(.plain)
                .disabled(!canSend)
                .accessibilityLabel(CommunityStrings.send)
            }
        }
        .padding(.horizontal, 20)
        .padding(.top, 12)
        .padding(.bottom, 8)
        .background(
            Rectangle()
                .fill(theme.colors.surface.shadow(.drop(color: .black.opacity(0.08), radius: 20, y: -24)))
                .ignoresSafeArea(edges: .bottom)
        )
    }

    private var field: some View {
        HStack(alignment: .bottom, spacing: 8) {
            TextField(
                "",
                text: $draft,
                prompt: Text(placeholder).foregroundColor(theme.colors.textTertiary),
                axis: .vertical
            )
                .focused(isFocused)
                .font(theme.font(14))
                .foregroundStyle(theme.colors.textPrimary)
                .lineLimit(1...4)

            if imagesEnabled {
                PhotosPicker(selection: $pickerItem, matching: .images) {
                    CommunityIconView(
                        icon: .gallery,
                        size: 16,
                        color: theme.colors.textTertiary.opacity(canAttach ? 1 : 0.5)
                    )
                }
                .disabled(!canAttach)
                .accessibilityLabel(CommunityStrings.addPhoto)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .frame(minHeight: 38)
        .background(theme.colors.raised, in: RoundedRectangle(cornerRadius: theme.radius.card))
    }

    private var attachments: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(Array(pendingMedia.enumerated()), id: \.offset) { index, item in
                    ZStack(alignment: .topTrailing) {
                        AsyncImage(url: item.url) { phase in
                            if case .success(let image) = phase {
                                image.resizable().scaledToFill()
                            } else {
                                theme.colors.raised
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
                        theme.colors.raised
                        ProgressView().tint(theme.colors.accent)
                    }
                    .frame(width: 56, height: 56)
                    .clipShape(RoundedRectangle(cornerRadius: theme.radius.small))
                    .accessibilityLabel(CommunityStrings.addPhoto)
                }
            }
            .padding(.top, 4)
        }
    }
}
