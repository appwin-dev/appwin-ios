import SwiftUI

/// One post card in the feed.
///
/// The body is truncated to `feedPreviewLines` (a studio setting) with a "see
/// more" that expands in place: opening the detail screen to read three extra
/// lines would be one navigation too many.
struct PostCard: View {
    let post: CommunityPost
    let showTranslation: Bool
    let canReact: Bool
    let showViews: Bool
    /// Reaction kinds offered by the project config (long-press picker).
    var availableReactions: [CommunityReactionKind] = CommunityReactionKind.allCases
    let onTapPost: () -> Void
    let onTapAuthor: () -> Void
    /// Short tap on Like toggles this kind (usually `.like` or the first config kind).
    let onReact: (CommunityReactionKind) -> Void
    let onComment: () -> Void
    let onMore: () -> Void
    var onVote: ((String) -> Void)? = nil

    @Environment(\.communityTheme) private var theme
    @State private var isExpanded = false
    @State private var showsOriginal = false
    @State private var showsReactionPicker = false

    /// Text shown: the translation when there is one and the reader has not
    /// explicitly asked for the original.
    private var displayedBody: String {
        guard showTranslation, let translated = post.translatedBody, !showsOriginal else {
            return post.body
        }
        return translated
    }

    private var hasTranslation: Bool {
        showTranslation && post.translatedBody != nil
    }

    private var defaultReaction: CommunityReactionKind {
        availableReactions.first ?? .like
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            header

            if post.isPendingReview {
                pendingBanner
            }

            if !displayedBody.isEmpty {
                bodyText
            }

            if !post.media.isEmpty {
                PostMediaGrid(media: post.media)
            }

            if let poll = post.poll {
                PostPollView(poll: poll) { optionId in
                    onVote?(optionId)
                }
            }

            if canReact || post.commentCount > 0 || (showViews && post.viewCount > 0) {
                statsRow
            }

            Rectangle()
                .fill(theme.colors.border)
                .frame(height: 1)

            actions
        }
        .padding(16)
        .background(theme.colors.surface, in: RoundedRectangle(cornerRadius: theme.radius.card))
        .contentShape(Rectangle())
        .onTapGesture(perform: onTapPost)
    }

    // MARK: - Subviews

    /// Name · relative date on the first line; group name under the author.
    private var header: some View {
        HStack(spacing: 12) {
            Button(action: onTapAuthor) {
                CommunityAvatar(
                    url: post.author?.avatarUrl,
                    nickname: post.author?.nickname ?? "?",
                    size: 40
                )
            }
            .buttonStyle(.plain)

            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Text(post.author?.nickname ?? "")
                        .font(theme.font(15, weight: .semibold))
                        .foregroundStyle(theme.colors.textPrimary)
                        .lineLimit(1)
                    if post.hasAdminTag {
                        CommunityTeamBadge()
                    }
                    CommunityRelativeDate(date: post.publishedAt)
                    if post.isPinned {
                        Image(systemName: "pin.fill")
                            .font(.system(size: 10))
                            .foregroundStyle(theme.colors.textTertiary)
                    }
                }
                if !post.groupName.isEmpty {
                    Text(post.groupName)
                        .font(theme.font(12, weight: .medium))
                        .foregroundStyle(theme.colors.accent)
                        .lineLimit(1)
                }
            }

            Spacer(minLength: 0)

            Button(action: onMore) {
                Image(systemName: "ellipsis")
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundStyle(theme.colors.textTertiary)
                    .frame(width: 32, height: 32)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
        }
    }

    private var pendingBanner: some View {
        Text(CommunityStrings.pendingReview)
            .font(theme.font(12))
            .foregroundStyle(theme.colors.textSecondary)
            .padding(8)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                AppwinCommunityPalette.warning.opacity(0.12),
                in: RoundedRectangle(cornerRadius: theme.radius.small)
            )
    }

    private var bodyText: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(displayedBody)
                .font(theme.font(16))
                .foregroundStyle(theme.colors.textPrimary)
                .lineLimit(isExpanded ? nil : theme.previewLineLimit)
                .fixedSize(horizontal: false, vertical: true)

            HStack(spacing: 12) {
                // The button only shows when the text can really overflow.
                // Estimating by character count avoids a `GeometryReader` per
                // cell, which is expensive in a list.
                if !isExpanded, mayOverflow {
                    inlineButton(CommunityStrings.seeMore) { isExpanded = true }
                } else if isExpanded {
                    inlineButton(CommunityStrings.seeLess) { isExpanded = false }
                }

                if hasTranslation {
                    inlineButton(
                        showsOriginal ? CommunityStrings.translate : CommunityStrings.showOriginal
                    ) {
                        showsOriginal.toggle()
                    }
                }
            }
        }
    }

    /// Overflow heuristic: roughly 44 characters per line on a standard phone.
    /// A false positive is a "see more" that expands nothing - annoying but
    /// harmless; a false negative is text cut off with no way out, which is far
    /// worse. So it errs on the permissive side.
    private var mayOverflow: Bool {
        displayedBody.count > theme.previewLineLimit * 44
            || displayedBody.components(separatedBy: .newlines).count > theme.previewLineLimit
    }

    private func inlineButton(_ title: String, action: @escaping () -> Void) -> some View {
        Button(title, action: action)
            .font(theme.font(13, weight: .medium))
            .foregroundStyle(theme.colors.accent)
            .buttonStyle(.plain)
    }

    /// Left: reaction summary; right: comments · views.
    private var statsRow: some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            if canReact {
                if post.likeCount > 0 {
                    Text("\(reactionSummaryEmoji) \(post.likeCount)")
                        .font(theme.font(13))
                        .foregroundStyle(theme.colors.textSecondary)
                } else {
                    Text(CommunityStrings.beFirstToReact)
                        .font(theme.font(13))
                        .foregroundStyle(theme.colors.textTertiary)
                }
            }

            Spacer(minLength: 0)

            HStack(spacing: 0) {
                Text(CommunityStrings.commentCountShort(post.commentCount))
                if showViews {
                    Text(" · ")
                    Text(CommunityStrings.viewCountShort(post.viewCount))
                }
            }
            .font(theme.font(13))
            .foregroundStyle(theme.colors.textTertiary)
        }
    }

    private var reactionSummaryEmoji: String {
        post.myReaction?.emoji ?? "❤️"
    }

    private var actions: some View {
        HStack(spacing: 24) {
            if canReact {
                likeAction
            }
            CommunityActionButton(
                systemImage: "bubble.left",
                label: CommunityStrings.comment,
                action: onComment
            )
            Spacer(minLength: 0)
        }
        .overlay(alignment: .topLeading) {
            if showsReactionPicker {
                reactionPicker
                    .offset(y: -52)
            }
        }
    }

    private var likeAction: some View {
        CommunityActionButton(
            systemImage: post.myReaction == nil ? "heart" : "heart.fill",
            label: CommunityStrings.like,
            isActive: post.myReaction != nil,
            action: { onReact(defaultReaction) }
        )
        .simultaneousGesture(
            LongPressGesture(minimumDuration: 0.35)
                .onEnded { _ in
                    guard availableReactions.count > 1 else { return }
                    withAnimation(.easeOut(duration: 0.15)) {
                        showsReactionPicker = true
                    }
                }
        )
    }

    private var reactionPicker: some View {
        HStack(spacing: 4) {
            ForEach(availableReactions, id: \.self) { kind in
                Button {
                    onReact(kind)
                    withAnimation(.easeOut(duration: 0.12)) {
                        showsReactionPicker = false
                    }
                } label: {
                    Text(kind.emoji)
                        .font(.system(size: 28))
                        .padding(6)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(theme.colors.surface, in: Capsule())
        .shadow(color: .black.opacity(0.12), radius: 8, y: 2)
        .onTapGesture {} // keep card tap from firing
        .background(
            Color.clear
                .contentShape(Rectangle())
                .frame(width: 400, height: 400)
                .onTapGesture {
                    showsReactionPicker = false
                }
        )
    }
}

/// Image grid of a post.
///
/// A single image keeps its aspect ratio; beyond that it switches to a square
/// grid, which is what keeps a series of photos readable without blowing up the
/// cell height.
struct PostMediaGrid: View {
    let media: [CommunityMedia]

    @Environment(\.communityTheme) private var theme

    var body: some View {
        switch media.count {
        case 0:
            EmptyView()
        case 1:
            mediaImage(media[0])
                .aspectRatio(media[0].aspectRatio ?? 4 / 3, contentMode: .fit)
                .clipShape(RoundedRectangle(cornerRadius: theme.radius.small))
        default:
            LazyVGrid(
                columns: [
                    GridItem(.flexible(), spacing: 4),
                    GridItem(.flexible(), spacing: 4),
                ],
                spacing: 4
            ) {
                // Past four, the surplus hides behind a counter rather than
                // growing the cell indefinitely.
                ForEach(media.prefix(4)) { item in
                    mediaImage(item)
                        .aspectRatio(1, contentMode: .fill)
                        .frame(maxWidth: .infinity)
                        .clipped()
                        .clipShape(RoundedRectangle(cornerRadius: theme.radius.small))
                        .overlay(alignment: .bottomTrailing) {
                            if item.id == media[3].id, media.count > 4 {
                                Text("+\(media.count - 4)")
                                    .font(theme.font(13, weight: .semibold))
                                    .foregroundStyle(.white)
                                    .padding(6)
                                    .background(.black.opacity(0.55), in: Capsule())
                                    .padding(6)
                            }
                        }
                }
            }
        }
    }

    private func mediaImage(_ item: CommunityMedia) -> some View {
        AsyncImage(url: item.url) { phase in
            switch phase {
            case .success(let image):
                image.resizable().scaledToFill()
            case .failure:
                theme.colors.border.overlay(
                    Image(systemName: "photo")
                        .foregroundStyle(theme.colors.textTertiary)
                )
            default:
                theme.colors.border.opacity(0.4)
            }
        }
        .accessibilityLabel(item.alt ?? "")
    }
}

struct PostPollView: View {
    let poll: CommunityPoll
    let onVote: (String) -> Void

    @Environment(\.communityTheme) private var theme

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            ForEach(poll.options) { option in
                let selected = poll.myOptionId == option.id
                let ratio = poll.totalVotes > 0
                    ? CGFloat(option.voteCount) / CGFloat(poll.totalVotes)
                    : 0
                Button {
                    guard poll.myOptionId == nil else { return }
                    onVote(option.id)
                } label: {
                    ZStack(alignment: .leading) {
                        RoundedRectangle(cornerRadius: theme.radius.small)
                            .fill(theme.colors.border.opacity(0.35))
                        if poll.myOptionId != nil {
                            GeometryReader { geo in
                                RoundedRectangle(cornerRadius: theme.radius.small)
                                    .fill(theme.colors.accent.opacity(selected ? 0.35 : 0.15))
                                    .frame(width: geo.size.width * ratio)
                            }
                        }
                        HStack {
                            Text(option.text)
                                .font(theme.font(14, weight: selected ? .semibold : .medium))
                                .foregroundStyle(theme.colors.textPrimary)
                            Spacer()
                            if poll.myOptionId != nil {
                                Text("\(option.voteCount)")
                                    .font(theme.font(13))
                                    .foregroundStyle(theme.colors.textSecondary)
                            }
                        }
                        .padding(.horizontal, 12)
                        .padding(.vertical, 10)
                    }
                    .frame(minHeight: 40)
                }
                .buttonStyle(.plain)
                .disabled(poll.myOptionId != nil)
            }
            if poll.totalVotes > 0 {
                Text(CommunityStrings.pollVotes(poll.totalVotes))
                    .font(theme.font(12))
                    .foregroundStyle(theme.colors.textTertiary)
            }
        }
    }
}
