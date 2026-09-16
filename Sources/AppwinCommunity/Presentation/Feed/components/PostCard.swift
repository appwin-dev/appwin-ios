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
    let onTapPost: () -> Void
    let onTapAuthor: () -> Void
    let onLike: () -> Void
    let onComment: () -> Void
    let onMore: () -> Void

    @Environment(\.communityTheme) private var theme
    @State private var isExpanded = false
    @State private var showsOriginal = false

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

            if showViews, post.viewCount > 0 {
                viewsRow
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

    /// Figma `card-header` (2120:24366): 40pt avatar, name over relative date.
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
                    if post.author?.isTeam == true || post.hasAdminTag {
                        CommunityTeamBadge()
                    }
                }
                HStack(spacing: 6) {
                    CommunityRelativeDate(date: post.publishedAt)
                    if post.isPinned {
                        Image(systemName: "pin.fill")
                            .font(.system(size: 10))
                            .foregroundStyle(theme.colors.textTertiary)
                    }
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

    /// Figma `views-row` (2120:24376): views alone, right-aligned, above the rule.
    private var viewsRow: some View {
        HStack(spacing: 4) {
            Spacer(minLength: 0)
            Image(systemName: "eye")
                .font(.system(size: 14))
            Text("\(post.viewCount)")
                .font(theme.font(12))
        }
        .foregroundStyle(theme.colors.textTertiary)
    }

    /// Figma `card-actions` (2120:24381).
    ///
    /// The counts live on the buttons rather than on a separate row: the mock
    /// reads "451 Likes", and printing the same number twice per card was the
    /// old layout's real flaw, not its spacing.
    private var actions: some View {
        HStack(spacing: 24) {
            if canReact {
                CommunityActionButton(
                    systemImage: post.myReaction == nil ? "heart" : "heart.fill",
                    label: CommunityStrings.reactionCount(post.likeCount),
                    isActive: post.myReaction != nil,
                    action: onLike
                )
            }
            CommunityActionButton(
                systemImage: "bubble.left",
                label: CommunityStrings.commentCount(post.commentCount),
                action: onComment
            )
            Spacer(minLength: 0)
        }
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
