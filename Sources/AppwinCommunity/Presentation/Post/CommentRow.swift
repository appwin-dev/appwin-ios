import SwiftUI

/// Comment row, with its replies indented - Figma commentary (19:5233, 178:2456):
/// a 24pt avatar and a bg/low bubble holding the author line, the body, then
/// « Répondre » and the reaction summary. A long press opens the emoji bar,
/// « ⋯ » the actions.
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
    /// The « ⋯ » menu; off where the comment is shown for a decision (moderation queue).
    var showsActions = true
    var onExpandReplies: (() -> Void)? = nil
    var onOpenProfile: ((CommunityComment) -> Void)? = nil

    @Environment(\.communityTheme) private var theme
    @State private var showsReactionBreakdown = false
    @State private var showsReactionBar = false

    private var displayedBody: String {
        showTranslation ? (comment.translatedBody ?? comment.body) : comment.body
    }

    private var defaultReaction: CommunityReactionKind {
        .defaultTap(from: availableReactions)
    }

    private var offersEmojis: Bool { availableReactions.count > 1 }

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
                authorAvatar.communityReactionDimmed(cornerRadius: 12)
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
                .communityReactionDimmed(cornerRadius: 4)
                .padding(.leading, 32)
            }
        }
        .sheet(isPresented: $showsReactionBreakdown) {
            ReactionBreakdownSheet(
                counts: comment.reactionCounts,
                total: comment.likeCount
            )
                .presentationDetents([.medium])
                .presentationDragIndicator(.visible)
        }
    }

    @ViewBuilder
    private var authorAvatar: some View {
        let avatar = CommunityAuthorAvatar(author: comment.author, size: 24)
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
                    if showsActions {
                        CommunityActionsMenu(target: .comment(comment)) {
                            Image(systemName: "ellipsis")
                                .font(.system(size: 12, weight: .semibold))
                                .foregroundStyle(theme.colors.textTertiary)
                                .frame(width: 44, height: 24, alignment: .trailing)
                                .contentShape(Rectangle())
                        }
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

            HStack(spacing: 8) {
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
                Spacer(minLength: 0)
                if canReact {
                    reactionButton
                }
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            showsReactionBar ? theme.colors.surface : theme.colors.raised,
            in: RoundedRectangle(cornerRadius: theme.radius.field)
        )
        .contentShape(RoundedRectangle(cornerRadius: theme.radius.field))
        .communityPress(
            onTap: { if showsReactionBar { closeReactionBar() } },
            onLongPress: {
                guard canReact else { return }
                if offersEmojis {
                    withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) { showsReactionBar = true }
                } else if comment.canEdit, comment.likeCount > 0 {
                    showsReactionBreakdown = true
                }
            }
        )
        .communityReactionFocusable(
            id: "comment:\(comment.id)",
            isActive: $showsReactionBar,
            cornerRadius: theme.radius.field
        )
        .overlay(alignment: .topLeading) {
            if showsReactionBar {
                CommunityReactionBar(reactions: availableReactions, selected: comment.myReaction) { kind in
                    onReact(comment, kind)
                    closeReactionBar()
                }
                .fixedSize(horizontal: false, vertical: true)
                .offset(x: -24, y: -60)
                .transition(.scale(scale: 0.6, anchor: .bottomLeading).combined(with: .opacity))
            }
        }
    }

    private func closeReactionBar() {
        withAnimation(.easeOut(duration: 0.15)) { showsReactionBar = false }
    }

    /// Figma: the three most used emojis and the count; a lone heart until someone reacts.
    private var reactionButton: some View {
        Button { onReact(comment, comment.myReaction ?? defaultReaction) } label: {
            if comment.likeCount > 0 {
                CommunityReactionSummary(top: summaryKinds, count: comment.likeCount)
            } else {
                Image(systemName: "heart")
                    .font(.system(size: 13))
                    .foregroundStyle(theme.colors.textTertiary)
            }
        }
        .buttonStyle(.plain)
        .accessibilityLabel(CommunityStrings.like)
    }

    private var summaryKinds: [CommunityReactionKind] {
        if !comment.topReactions.isEmpty { return comment.topReactions }
        return [comment.myReaction ?? defaultReaction]
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
}
