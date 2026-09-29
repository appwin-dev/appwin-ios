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
    /// Nil when public profiles are off - avatar stays non-interactive.
    var onTapAuthor: (() -> Void)? = nil
    /// Short tap on Like toggles this kind (usually `.like` or the first config kind).
    let onReact: (CommunityReactionKind) -> Void
    let onComment: () -> Void
    let onMore: () -> Void
    var onVote: ((String) -> Void)? = nil

    @Environment(\.communityTheme) private var theme
    @State private var isExpanded = false
    @State private var showsOriginal = false
    @State private var showsReactionPicker = false
    @State private var showsReactionBreakdown = false

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

    /// Long-press tray: studio-configured kinds when several are on, otherwise
    /// the full set (same idea as Support's fixed quick reactions).
    private var pickerReactions: [CommunityReactionKind] {
        availableReactions.count > 1 ? availableReactions : Array(CommunityReactionKind.allCases)
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
                PostPollView(
                    poll: poll,
                    // Authors see tallies without voting first (`canEdit` = mine).
                    showsResults: poll.myOptionId != nil || post.canEdit
                ) { optionId in
                    onVote?(optionId)
                }
            }

            if canReact || post.commentCount > 0 || (showViews && post.viewCount > 0) {
                statsRow
                    .zIndex(1)
            }

            Rectangle()
                .fill(theme.colors.border)
                .frame(height: 1)

            actions
                .zIndex(1)
        }
        .padding(16)
        .background(theme.colors.surface, in: RoundedRectangle(cornerRadius: theme.radius.card))
        .contentShape(Rectangle())
        .onTapGesture(perform: onTapPost)
        .sheet(isPresented: $showsReactionBreakdown) {
            ReactionBreakdownSheet(counts: post.reactionCounts, total: post.likeCount)
                .presentationDetents([.medium])
                .presentationDragIndicator(.visible)
        }
    }

    // MARK: - Subviews

    /// Name · relative date on the first line; group name under the author.
    private var header: some View {
        HStack(alignment: .top, spacing: 12) {
            authorAvatar

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
                    Spacer(minLength: 0)
                    Button(action: onMore) {
                        Image(systemName: "ellipsis")
                            .font(.system(size: 17, weight: .semibold))
                            .foregroundStyle(theme.colors.textTertiary)
                            .frame(width: 44, height: 32)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                }
                if !post.groupName.isEmpty {
                    Text(post.groupName)
                        .font(theme.font(12, weight: .medium))
                        .foregroundStyle(theme.colors.accent)
                        .lineLimit(1)
                }
            }
        }
        .zIndex(1)
    }

    @ViewBuilder
    private var authorAvatar: some View {
        let avatar = CommunityAvatar(
            url: post.author?.avatarUrl,
            nickname: post.author?.nickname ?? "?",
            size: 40
        )
        if let onTapAuthor {
            Button(action: onTapAuthor) { avatar }
                .buttonStyle(.plain)
        } else {
            avatar
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
                    Button {
                        showsReactionBreakdown = true
                    } label: {
                        Text("\(reactionSummaryEmojis) \(post.likeCount)")
                            .font(theme.font(13))
                            .foregroundStyle(theme.colors.textSecondary)
                    }
                    .buttonStyle(.plain)
                } else {
                    Text(CommunityStrings.beFirstToReact)
                        .font(theme.font(13))
                        .foregroundStyle(theme.colors.textTertiary)
                }
            }

            Spacer(minLength: 0)

            // Explicit Button so a leaked media hit target cannot swallow this tap.
            Button(action: onComment) {
                HStack(spacing: 0) {
                    Text(CommunityStrings.commentCountShort(post.commentCount))
                    if showViews {
                        Text(" · ")
                        Text(CommunityStrings.viewCountShort(post.viewCount))
                    }
                }
                .font(theme.font(13))
                .foregroundStyle(theme.colors.textTertiary)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
        }
    }

    private var reactionSummaryEmojis: String {
        let kinds: [CommunityReactionKind]
        if !post.topReactions.isEmpty {
            kinds = Array(post.topReactions.prefix(3))
        } else if !post.reactionCounts.isEmpty {
            kinds = post.reactionCounts.sorted { $0.count > $1.count }.prefix(3).map(\.kind)
        } else {
            kinds = [post.myReaction].compactMap { $0 }
        }
        let emojis = kinds.map(\.emoji)
        return emojis.isEmpty ? "❤️" : emojis.joined()
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
                    withAnimation(.easeOut(duration: 0.15)) {
                        showsReactionPicker = true
                    }
                }
        )
    }

    private var reactionPicker: some View {
        HStack(spacing: 4) {
            ForEach(pickerReactions, id: \.self) { kind in
                Button {
                    onReact(kind)
                    withAnimation(.easeOut(duration: 0.12)) {
                        showsReactionPicker = false
                    }
                } label: {
                    Text(kind.emoji)
                        .font(.system(size: 28))
                        .frame(width: 36, height: 36)
                        .background(
                            kind == post.myReaction
                                ? theme.colors.border.opacity(0.55)
                                : Color.clear,
                            in: RoundedRectangle(cornerRadius: 10)
                        )
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
/// A single image keeps its aspect ratio up to a portrait cap (4:5): taller
/// shots are cropped top/bottom so they do not dominate the feed. Multiple
/// images switch to a square grid.
struct PostMediaGrid: View {
    let media: [CommunityMedia]

    @Environment(\.communityTheme) private var theme

    /// Tallest single-media frame in the feed (width / height). Below this,
    /// top and bottom are cropped.
    private static let minSingleAspect: CGFloat = 4.0 / 5.0

    var body: some View {
        switch media.count {
        case 0:
            EmptyView()
        case 1:
            let natural = media[0].aspectRatio ?? (4.0 / 3.0)
            let display = max(natural, Self.minSingleAspect)
            // `aspectRatio(..., .fill)` does not cap height for AsyncImage; lock
            // a fit frame then fill+clip so tall photos crop top/bottom.
            // contentShape after clipShape confines hit-testing to the visible
            // rect: scaledToFill otherwise steals taps from the header ellipsis.
            Color.clear
                .aspectRatio(display, contentMode: .fit)
                .overlay {
                    mediaImage(media[0])
                }
                .clipShape(RoundedRectangle(cornerRadius: theme.radius.small))
                .contentShape(RoundedRectangle(cornerRadius: theme.radius.small))
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
                        .contentShape(RoundedRectangle(cornerRadius: theme.radius.small))
                        .overlay(alignment: .bottomTrailing) {
                            // Count first: `media[3]` traps when there are only 2–3 items.
                            if media.count > 4, item.id == media[3].id {
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
        Group {
            if item.isVideo {
                CommunityVideoThumbnail(media: item)
            } else {
                // onTapGesture (not Button) so the hit target stays in the clipped frame.
                CommunityTappableImage(url: item.url, alt: item.alt)
            }
        }
        .contentShape(Rectangle())
    }
}

struct PostPollView: View {
    let poll: CommunityPoll
    /// Voted members and the post author see bars / counts; others vote first.
    var showsResults: Bool = false
    let onVote: (String) -> Void

    @Environment(\.communityTheme) private var theme

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            ForEach(poll.options) { option in
                let selected = poll.myOptionId == option.id
                let ratio = poll.totalVotes > 0
                    ? CGFloat(option.voteCount) / CGFloat(poll.totalVotes)
                    : 0
                let hasVoted = poll.myOptionId != nil
                Button {
                    guard !hasVoted else { return }
                    onVote(option.id)
                } label: {
                    ZStack(alignment: .leading) {
                        RoundedRectangle(cornerRadius: theme.radius.small)
                            .fill(theme.colors.border.opacity(0.35))
                        if showsResults {
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
                            if showsResults {
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
                .disabled(hasVoted)
            }
            if poll.totalVotes > 0 {
                Text(CommunityStrings.pollVotes(poll.totalVotes))
                    .font(theme.font(12))
                    .foregroundStyle(theme.colors.textTertiary)
            }
        }
    }
}

/// Sheet listing each reaction kind with its count.
struct ReactionBreakdownSheet: View {
    let counts: [CommunityReactionCount]
    let total: Int

    @Environment(\.communityTheme) private var theme
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            List {
                ForEach(counts) { entry in
                    HStack(spacing: 12) {
                        Text(entry.kind.emoji)
                            .font(.system(size: 22))
                        Text(CommunityStrings.reactionLabel(entry.kind))
                            .font(theme.font(15))
                            .foregroundStyle(theme.colors.textPrimary)
                        Spacer()
                        Text("\(entry.count)")
                            .font(theme.font(15, weight: .semibold))
                            .foregroundStyle(theme.colors.textSecondary)
                    }
                    .listRowBackground(theme.colors.surface)
                }
            }
            .listStyle(.plain)
            .navigationTitle(CommunityStrings.reactionsTitle(total))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button(CommunityStrings.close) { dismiss() }
                        .foregroundStyle(theme.colors.accent)
                }
            }
        }
    }
}
