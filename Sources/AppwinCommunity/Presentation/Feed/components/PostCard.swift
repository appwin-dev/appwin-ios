import SwiftUI

/// One post card in the feed.
///
/// The body is truncated to `feedPreviewLines` (a studio setting) with a "see
/// more" that expands in place: opening the detail screen to read three extra
/// lines would be one navigation too many.
struct PostCard: View {
    /// Feed card, or flat and full-bleed at the top of the comments screen.
    enum Style { case card, flat }

    let post: CommunityPost
    let showTranslation: Bool
    let canReact: Bool
    let showViews: Bool
    /// Reaction kinds offered by the project config (long-press picker).
    var availableReactions: [CommunityReactionKind] = CommunityReactionKind.allCases
    var style: Style = .card
    let onTapPost: () -> Void
    /// Nil when public profiles are off - avatar stays non-interactive.
    var onTapAuthor: (() -> Void)? = nil
    /// Short tap on Like toggles this kind (usually `.like` or the first config kind).
    let onReact: (CommunityReactionKind) -> Void
    let onComment: () -> Void
    /// The « ⋯ » menu; off where the post is shown for a decision (moderation queue).
    var showsActions = true
    var onVote: ((String) -> Void)? = nil
    /// Moderation queue: the sanction in place of the « ⋯ » menu (Figma 182:857).
    var sanction: CommunitySanctionBadge.Kind? = nil

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
        .defaultTap(from: availableReactions)
    }

    /// The studio offers the emoji bar, not the heart alone.
    private var offersEmojis: Bool { availableReactions.count > 1 }

    /// Figma feed 5:1837: header, content, media inset by 4, actions.
    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
                .padding(.top, post.isPinned && style == .card ? 32 : 16)
                .padding(.horizontal, 16)

            VStack(alignment: .leading, spacing: 12) {
                if !displayedBody.isEmpty {
                    bodyText
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
            }
            .padding(16)

            if !post.media.isEmpty {
                PostMediaGrid(media: post.media)
                    .padding(.horizontal, 4)
            }

            actions
                .padding(16)
                .overlay(alignment: .top) {
                    // A photo already closes the content; text and polls get a rule.
                    if post.media.isEmpty {
                        Rectangle().fill(theme.colors.raised).frame(height: 1)
                    }
                }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(theme.colors.surface)
        .clipShape(RoundedRectangle(cornerRadius: style == .card ? theme.radius.card : 0))
        .contentShape(Rectangle())
        .onTapGesture(perform: onTapPost)
        .overlay(alignment: .topTrailing) {
            if sanction == nil, showsActions { actionsMenu }
        }
        .overlay(alignment: .top) {
            if post.isPinned && style == .card {
                pinnedBadge
                    .communityReactionDimmed(cornerRadius: 999, ownerId: "post:\(post.id)")
                    .offset(y: -12)
            }
        }
        // After clipShape so the tray is not cropped, and outside the actions
        // row so a dismiss backdrop cannot inflate the picker layout.
        .overlay {
            if showsReactionPicker {
                ZStack(alignment: .bottomLeading) {
                    Color.clear
                        .contentShape(Rectangle())
                        .onTapGesture(perform: closeReactionPicker)
                    reactionPicker
                        .padding(.leading, 12)
                        .padding(.bottom, 52)
                        .transition(.scale(scale: 0.6, anchor: .bottomLeading).combined(with: .opacity))
                }
            }
        }
        .communityReactionFocusable(
            id: "post:\(post.id)",
            isActive: $showsReactionPicker,
            cornerRadius: style == .card ? theme.radius.card : 0
        )
        .sheet(isPresented: $showsReactionBreakdown) {
            ReactionBreakdownSheet(
                counts: post.reactionCounts,
                total: post.likeCount
            )
                .presentationDetents([.medium])
                .presentationDragIndicator(.visible)
        }
    }

    // MARK: - Subviews

    /// Name, team chip and relative date on the first line; `#group` under it.
    private var header: some View {
        HStack(alignment: .top, spacing: 8) {
            HStack(spacing: 8) {
                authorAvatar

                // spacing 0: SwiftUI Text line boxes already leave a few pt
                // under the glyph; VStack spacing: 2 stacked on that and the
                // #group looked a full line away from the nickname (Flutter
                // host on device). Android Compose uses 2.dp on tighter metrics.
                VStack(alignment: .leading, spacing: 0) {
                    HStack(alignment: .firstTextBaseline, spacing: 6) {
                        Text(post.author?.nickname ?? "")
                            .font(theme.font(14, weight: .semibold))
                            .foregroundStyle(theme.colors.textPrimary)
                            .lineLimit(1)
                        if post.hasAdminTag {
                            CommunityTeamBadge()
                        }
                        CommunityRelativeDate(date: post.publishedAt)
                    }
                    if !post.groupName.isEmpty {
                        Text("#\(post.groupName)")
                            .font(theme.font(10, weight: .bold))
                            .foregroundStyle(theme.colors.textTertiary)
                            .lineLimit(1)
                            .padding(.top, 1)
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            if let sanction {
                CommunitySanctionBadge(kind: sanction)
            } else if showsActions {
                // Room for the « ⋯ », drawn over the card's corner (see `actionsMenu`).
                Color.clear.frame(width: 24, height: 24)
            }
        }
        .zIndex(1)
    }

    /// The « ⋯ » over the card's corner, padding included: a tap near the dots
    /// opened the post when only the glyph was a target.
    private var actionsMenu: some View {
        CommunityActionsMenu(target: .post(post)) {
            Image(systemName: "ellipsis")
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(theme.colors.textTertiary)
                .padding(.top, post.isPinned && style == .card ? 32 : 16)
                .padding(.trailing, 16)
                .frame(width: 80, height: post.isPinned && style == .card ? 76 : 60, alignment: .topTrailing)
                .contentShape(Rectangle())
        }
    }

    @ViewBuilder
    private var authorAvatar: some View {
        let avatar = CommunityAuthorAvatar(author: post.author, size: 40)
        if let onTapAuthor {
            Button(action: onTapAuthor) { avatar }
                .buttonStyle(.plain)
        } else {
            avatar
        }
    }

    /// Figma "Épinglé" (59:7694): a 24pt capsule of the accent at 24 % over
    /// bg/container, text/secondary, with a 4pt bg/container stroke drawn
    /// outside it that cuts it out of the card edge.
    private var pinnedBadge: some View {
        HStack(spacing: 4) {
            CommunityIconView(icon: .pin, size: 12, color: theme.colors.textSecondary)
            Text(CommunityStrings.pinned)
                .font(theme.font(10, weight: .bold))
                .foregroundStyle(theme.colors.textSecondary)
        }
        .padding(.horizontal, 8)
        .frame(height: 24)
        .background(
            Capsule()
                .fill(theme.colors.accent.opacity(0.24))
                .background(Capsule().fill(theme.colors.surface))
        )
        .padding(4)
        .background(Capsule().fill(theme.colors.surface))
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

    /// Like and comment counts on the left, views on the right.
    private var actions: some View {
        HStack(spacing: 24) {
            if canReact {
                likeAction
            }
            CommunityCountAction(
                icon: .chatLine,
                count: post.commentCount,
                accessibilityLabel: CommunityStrings.comment,
                action: onComment
            )
            Spacer(minLength: 0)
            HStack(spacing: 10) {
                if showViews {
                    Text(CommunityStrings.viewCountShort(post.viewCount))
                        .font(theme.font(12, weight: .medium))
                        .foregroundStyle(theme.colors.textTertiary)
                }
                if canReact, offersEmojis, !post.topReactions.isEmpty {
                    if showViews {
                        Rectangle().fill(theme.colors.border).frame(width: 1, height: 16)
                    }
                    Button {
                        // Who reacted how stays with the author.
                        if post.canEdit { showsReactionBreakdown = true }
                    } label: {
                        CommunityReactionSummary(top: post.topReactions)
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    /// Short tap toggles the default kind; a long press opens the emoji bar.
    private var likeAction: some View {
        HStack(spacing: 4) {
            likeGlyph
            Text("\(post.likeCount)")
                .font(theme.font(12, weight: .medium))
                .foregroundStyle(theme.colors.textTertiary)
        }
        .frame(minWidth: 64, minHeight: 32, alignment: .leading)
        .contentShape(Rectangle())
        .communityPress(
            // Same kind again removes it; only the empty state applies the
            // default heart. Otherwise a laugh tap would flip to the heart.
            onTap: { onReact(post.myReaction ?? defaultReaction) },
            onLongPress: {
                if offersEmojis {
                    withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                        showsReactionPicker = true
                    }
                } else if post.canEdit, post.likeCount > 0 {
                    showsReactionBreakdown = true
                }
            }
        )
        .accessibilityLabel(CommunityStrings.like)
        .accessibilityAddTraits(.isButton)
    }

    /// Always the heart: the emojis themselves live in the summary on the right.
    private var likeGlyph: some View {
        CommunityIconView(
            icon: post.myReaction == nil ? .heart : .heartFill,
            size: 20,
            color: post.myReaction == nil ? theme.colors.textTertiary : theme.colors.like
        )
    }

    private func closeReactionPicker() {
        withAnimation(.easeOut(duration: 0.15)) { showsReactionPicker = false }
    }

    private var reactionPicker: some View {
        CommunityReactionBar(reactions: availableReactions, selected: post.myReaction) { kind in
            onReact(kind)
            closeReactionPicker()
        }
        .onTapGesture {} // keep card tap from firing
    }
}

/// Image grid of a post.
///
/// A single image keeps its aspect ratio up to a portrait cap (4:5): taller
/// shots are cropped top/bottom so they do not dominate the feed. Two images sit
/// side by side at the Figma 300pt height; more switch to a square grid.
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
        case 2:
            HStack(spacing: 4) {
                ForEach(media) { item in
                    Color.clear
                        .frame(maxWidth: .infinity)
                        .frame(height: 300)
                        .overlay { mediaImage(item) }
                        .clipShape(RoundedRectangle(cornerRadius: theme.radius.small))
                        .contentShape(RoundedRectangle(cornerRadius: theme.radius.small))
                }
            }
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

/// Figma poll choices: bg/low options; once results show, a bar fills each
/// option in proportion (the accent for the member's own vote) and the
/// percentage sits on the right.
struct PostPollView: View {
    let poll: CommunityPoll
    /// Voted members and the post author see bars / counts; others vote first.
    var showsResults: Bool = false
    let onVote: (String) -> Void

    @Environment(\.communityTheme) private var theme

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            ForEach(poll.options) { option in
                let selected = poll.myOptionId == option.id
                let ratio = poll.totalVotes > 0
                    ? CGFloat(option.voteCount) / CGFloat(poll.totalVotes)
                    : 0
                let hasVoted = poll.myOptionId != nil
                let shape = RoundedRectangle(cornerRadius: theme.radius.field)
                Button {
                    guard !hasVoted else { return }
                    onVote(option.id)
                } label: {
                    HStack(spacing: 8) {
                        Text(option.text)
                            .font(theme.font(14, weight: .medium))
                            .foregroundStyle(selected ? theme.colors.onAccent : theme.colors.textPrimary)
                            .frame(maxWidth: .infinity, alignment: .leading)
                        if showsResults {
                            Text("\(Int((ratio * 100).rounded()))%")
                                .font(theme.font(12, weight: .medium))
                                .foregroundStyle(theme.colors.textPrimary)
                        }
                    }
                    .padding(16)
                    .background(alignment: .leading) {
                        if showsResults {
                            GeometryReader { geo in
                                shape
                                    .fill(selected ? theme.accentFill : AnyShapeStyle(theme.colors.border))
                                    .frame(width: geo.size.width * ratio)
                            }
                        }
                    }
                    .background(showsResults && selected ? theme.accentSoft : theme.colors.raised)
                    .clipShape(shape)
                    .contentShape(shape)
                }
                .buttonStyle(.plain)
                // Not `.disabled`: it would dim the results, which Figma keeps
                // at full contrast.
                .allowsHitTesting(!hasVoted)
                .accessibilityAddTraits(hasVoted ? .isStaticText : [])
            }
        }
    }
}

/// Read-only sheet listing each reaction kind with its count (author view).
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
