import SwiftUI

/// The bell's inbox: unread sanctions on top, each waiting for its « Got it »,
/// then what other members did around the member's content, newest first.
/// Opening it reads the activity, which clears the tab's dot.
struct NotificationsView: View {
    /// Opens the entry's post, or its reply thread.
    let onOpen: (CommunityPushTarget) -> Void

    @EnvironmentObject private var session: CommunitySession
    @Environment(\.communityTheme) private var theme
    @State private var sanctions: [CommunityNotification] = []
    @State private var activity: [CommunityActivity] = []
    @State private var isLoading = true
    @State private var loadFailed = false
    @State private var reachedEnd = false

    private static let pageSize = 20

    var body: some View {
        // One stable ScrollView, never a plain ProgressView: swapping the
        // container flips the inline nav bar between its standard and
        // scroll-edge appearances and nudges the back button.
        GeometryReader { proxy in
            ScrollView {
                Group {
                    if isLoading && sanctions.isEmpty && activity.isEmpty {
                        ProgressView().tint(theme.colors.accent)
                            .frame(maxWidth: .infinity, minHeight: proxy.size.height + 1)
                    } else if sanctions.isEmpty && activity.isEmpty {
                        CommunityEmptyState(
                            icon: .bell,
                            title: loadFailed ? CommunityStrings.loadErrorTitle : CommunityStrings.notificationsEmpty,
                            message: loadFailed ? CommunityStrings.loadErrorMessage : CommunityStrings.notificationsEmptyHint,
                            actionTitle: loadFailed ? CommunityStrings.retry : nil,
                            action: loadFailed ? { Task { await load() } } : nil
                        )
                        .frame(maxWidth: .infinity, minHeight: proxy.size.height + 1)
                    } else {
                        list.frame(maxWidth: .infinity, minHeight: proxy.size.height + 1, alignment: .top)
                    }
                }
            }
            .background(theme.colors.background.ignoresSafeArea())
        }
        .navigationTitle(CommunityStrings.notificationsTitle)
        .navigationBarTitleDisplayMode(.inline)
        .task { await load() }
    }

    private var list: some View {
        LazyVStack(alignment: .leading, spacing: 0) {
            if !sanctions.isEmpty {
                VStack(alignment: .leading, spacing: 40) {
                    ForEach(sanctions) { sanction in
                        SanctionCard(
                            sanction: sanction,
                            teamName: session.config.context.projectName,
                            author: session.profile,
                            onUnderstood: { acknowledge(sanction) }
                        )
                    }
                }
                .padding(.horizontal, 20)
                .padding(.vertical, 16)
            }
            ForEach(activity) { entry in
                ActivityRow(entry: entry) {
                    guard let postId = entry.postId else { return }
                    onOpen(CommunityPushTarget(postId: postId, threadCommentId: entry.threadCommentId))
                }
                .task { await loadMoreIfNeeded(after: entry) }
            }
        }
        .padding(.bottom, 32)
    }

    /// Lists first, then marks read: the entries of this visit still show as new.
    private func load() async {
        isLoading = true
        loadFailed = false
        defer { isLoading = false }
        async let sanctionsResult = try? Factory.moderationRepository().sanctions()
        async let activityResult = try? Factory.repository().activity(limit: Self.pageSize, offset: 0)
        let (loadedSanctions, loadedActivity) = await (sanctionsResult, activityResult)
        if let loadedSanctions {
            sanctions = loadedSanctions.filter { !$0.isRead }
            session.setUnreadSanctionCount(sanctions.count)
        }
        guard let loadedActivity else {
            loadFailed = true
            return
        }
        activity = loadedActivity
        reachedEnd = loadedActivity.count < Self.pageSize
        await session.markNotificationsSeen()
    }

    private func loadMoreIfNeeded(after entry: CommunityActivity) async {
        guard entry.id == activity.last?.id, !reachedEnd, !isLoading else { return }
        isLoading = true
        defer { isLoading = false }
        guard let page = try? await Factory.repository().activity(limit: Self.pageSize, offset: activity.count)
        else { return }
        let known = Set(activity.map(\.id))
        activity.append(contentsOf: page.filter { !known.contains($0.id) })
        reachedEnd = page.count < Self.pageSize
    }

    private func acknowledge(_ sanction: CommunityNotification) {
        withAnimation { sanctions.removeAll { $0.id == sanction.id } }
        session.setUnreadSanctionCount(sanctions.count)
        Task { try? await Factory.moderationRepository().acknowledge(notificationIds: [sanction.id]) }
    }
}

/// One inbox entry: the newest actors' avatars, « **Marie** and 3 others liked
/// your post », the content's words, when. A new entry is tinted and dotted.
private struct ActivityRow: View {
    let entry: CommunityActivity
    let onTap: () -> Void

    @Environment(\.communityTheme) private var theme

    var body: some View {
        Button(action: onTap) {
            HStack(alignment: .top, spacing: 12) {
                avatars
                VStack(alignment: .leading, spacing: 4) {
                    Text(sentence)
                        .font(theme.font(14))
                        .foregroundStyle(theme.colors.textPrimary)
                        .fixedSize(horizontal: false, vertical: true)
                    if let excerpt = entry.excerpt?.trimmingCharacters(in: .whitespacesAndNewlines),
                       !excerpt.isEmpty {
                        Text(excerpt)
                            .font(theme.font(14))
                            .foregroundStyle(theme.colors.textSecondary)
                            .lineLimit(2)
                    }
                    CommunityRelativeDate(date: entry.createdAt)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                if !entry.isRead {
                    Circle()
                        .fill(theme.colors.accent)
                        .frame(width: 8, height: 8)
                        .padding(.top, 6)
                }
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 12)
            .background(entry.isRead ? Color.clear : theme.colors.accent.opacity(0.06))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    /// The newest actor in front; a second one peeks behind for a group.
    private var avatars: some View {
        let first = entry.actors.first
        return ZStack(alignment: .bottomTrailing) {
            CommunityAvatar(url: first?.avatarUrl, nickname: first?.nickname ?? "", size: 40)
            if entry.actorCount > 1, entry.actors.count > 1 {
                CommunityAvatar(url: entry.actors[1].avatarUrl, nickname: entry.actors[1].nickname, size: 22)
                    .overlay(Circle().strokeBorder(theme.colors.background, lineWidth: 2))
                    .offset(x: 6, y: 4)
            }
        }
        .frame(width: 40, height: 40)
    }

    private var sentence: AttributedString {
        let name = entry.actors.first.map { Self.escapingMarkdown($0.nickname) } ?? CommunityStrings.activitySomeone
        let others = entry.actorCount > 1 ? CommunityStrings.activityOthers(entry.actorCount - 1) : nil
        let markdown = CommunityStrings.activitySentence(entry.type, actor: name, others: others)
        return (try? AttributedString(
            markdown: markdown,
            options: .init(interpretedSyntax: .inlineOnlyPreservingWhitespace)
        )) ?? AttributedString(markdown)
    }

    /// A nickname is the member's own text: `*` or `_` in it must not turn
    /// the sentence's bold inside out.
    private static func escapingMarkdown(_ text: String) -> String {
        var escaped = ""
        for character in text {
            if "\\*_`[]~".contains(character) { escaped.append("\\") }
            escaped.append(character)
        }
        return escaped
    }
}
