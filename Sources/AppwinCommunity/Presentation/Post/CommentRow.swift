import SwiftUI

/// Comment row, with its replies indented - Figma commentary (19:5233): a 24pt
/// avatar and a bg/low bubble holding the author line, the body, the like
/// counter (top right) and "Répondre".
///
/// Figma draws no menu: delete / report and the other reaction kinds live in
/// the bubble's long-press menu.
struct CommentRow: View {
    let comment: CommunityComment
    let depth: Int
    let canReact: Bool
    let canReply: Bool
    let showTranslation: Bool
    var availableReactions: [CommunityReactionKind] = CommunityReactionKind.allCases
    /// When false, the parent screen lists replies itself (dedicated thread view).
    var embedReplies: Bool = true
    let onReact: (CommunityComment, CommunityReactionKind) -> Void
    let onReply: (CommunityComment) -> Void
    let onDelete: (CommunityComment) -> Void
    let onReport: (CommunityComment) -> Void
    var onExpandReplies: (() -> Void)? = nil
    var onOpenProfile: ((CommunityComment) -> Void)? = nil

    @Environment(\.communityTheme) private var theme
    @State private var showsReactionBreakdown = false

    private var displayedBody: String {
        showTranslation ? (comment.translatedBody ?? comment.body) : comment.body
    }

    private var defaultReaction: CommunityReactionKind {
        availableReactions.first ?? .like
    }

    private var shouldCollapseReplies: Bool {
        // One reply stays inline; from the second on, "Show N replies".
        embedReplies && depth == 0 && comment.replyCount > 1
    }

    private var showsRepliesInline: Bool {
        embedReplies && !comment.replies.isEmpty && !shouldCollapseReplies
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .top, spacing: 8) {
                authorAvatar
                bubble
            }

            if showsRepliesInline {
                ForEach(comment.replies) { reply in
                    CommentRow(
                        comment: reply,
                        depth: depth + 1,
                        canReact: canReact,
                        canReply: canReply,
                        showTranslation: showTranslation,
                        availableReactions: availableReactions,
                        onReact: onReact,
                        onReply: onReply,
                        onDelete: onDelete,
                        onReport: onReport,
                        onOpenProfile: onOpenProfile
                    )
                    .padding(.leading, 32)
                }
            }

            if shouldCollapseReplies {
                Button {
                    onExpandReplies?()
                } label: {
                    HStack(spacing: 4) {
                        Rectangle()
                            .fill(theme.colors.border)
                            .frame(width: 20, height: 1)
                        Text(CommunityStrings.showReplies(comment.replyCount))
                            .font(theme.font(12, weight: .semibold))
                        Image(systemName: "chevron.down")
                            .font(.system(size: 9, weight: .semibold))
                    }
                    .foregroundStyle(theme.colors.textTertiary)
                }
                .buttonStyle(.plain)
                .padding(.leading, 32)
            }
        }
        .sheet(isPresented: $showsReactionBreakdown) {
            ReactionBreakdownSheet(counts: comment.reactionCounts, total: comment.likeCount)
                .presentationDetents([.medium])
                .presentationDragIndicator(.visible)
        }
    }

    @ViewBuilder
    private var authorAvatar: some View {
        let avatar = CommunityAvatar(
            url: comment.author?.avatarUrl,
            nickname: comment.author?.nickname ?? "?",
            size: 24
        )
        if let onOpenProfile, let author = comment.author, author.isAddressable {
            Button { onOpenProfile(comment) } label: { avatar }
                .buttonStyle(.plain)
        } else {
            avatar
        }
    }

    private var bubble: some View {
        VStack(alignment: .leading, spacing: 10) {
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Text(comment.author?.nickname ?? "")
                        .font(theme.font(12, weight: .semibold))
                        .foregroundStyle(theme.colors.textPrimary)
                        .lineLimit(1)
                    if comment.author?.isTeam == true {
                        CommunityTeamBadge(compact: true)
                    }
                    CommunityRelativeDate(date: comment.createdAt, size: 10)
                    Spacer(minLength: 8)
                    if canReact {
                        likeButton
                    }
                }

                if !displayedBody.isEmpty {
                    Text(displayedBody)
                        .font(theme.font(14))
                        .foregroundStyle(theme.colors.textPrimary)
                        .fixedSize(horizontal: false, vertical: true)
                }

                if !comment.media.isEmpty {
                    media
                        .padding(.top, 4)
                }
            }

            // Reply is allowed on replies too: the API re-parents under the
            // root so the thread stays one level deep.
            if canReply {
                Button { onReply(comment) } label: {
                    Text(CommunityStrings.reply)
                        .font(theme.font(12, weight: .semibold))
                        .foregroundStyle(theme.colors.textTertiary)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(theme.colors.raised, in: RoundedRectangle(cornerRadius: theme.radius.field))
        .contentShape(.contextMenuPreview, RoundedRectangle(cornerRadius: theme.radius.field))
        .contextMenu { menu }
    }

    private var likeButton: some View {
        Button { onReact(comment, defaultReaction) } label: {
            HStack(spacing: 2) {
                Text("\(comment.likeCount)")
                    .font(theme.font(12, weight: .medium))
                Image(systemName: comment.myReaction == nil ? "heart" : "heart.fill")
                    .font(.system(size: 13))
            }
            .foregroundStyle(comment.myReaction == nil ? theme.colors.textTertiary : theme.colors.like)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(CommunityStrings.like)
    }

    private var media: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 6) {
                ForEach(comment.media) { item in
                    Group {
                        if item.isVideo {
                            CommunityVideoThumbnail(media: item)
                        } else {
                            CommunityTappableImage(url: item.url, alt: item.alt)
                        }
                    }
                    .frame(width: 120, height: 120)
                    .clipShape(RoundedRectangle(cornerRadius: theme.radius.small))
                }
            }
        }
    }

    @ViewBuilder
    private var menu: some View {
        if canReact, availableReactions.count > 1 {
            ForEach(availableReactions, id: \.self) { kind in
                Button("\(kind.emoji) \(CommunityStrings.reactionLabel(kind))") {
                    onReact(comment, kind)
                }
            }
        }
        if comment.likeCount > 0 {
            Button(CommunityStrings.reactionsTitle(comment.likeCount)) {
                showsReactionBreakdown = true
            }
        }
        if comment.canDelete {
            Button(CommunityStrings.delete, role: .destructive) { onDelete(comment) }
        } else {
            Button(CommunityStrings.report) { onReport(comment) }
        }
    }
}
