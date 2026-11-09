import SwiftUI

/// A moderator answers the author of a queued content. The answer is a plain
/// comment under the post: a hidden post stays hidden from the community, but
/// its author still sees it, and the comment with it.
struct ModerationReplySheet: View {
    let item: ModerationQueueItem

    @EnvironmentObject private var session: CommunitySession
    @Environment(\.communityTheme) private var theme
    @Environment(\.dismiss) private var dismiss
    @State private var text = ""
    @State private var isSending = false
    @State private var isSent = false
    @State private var failed = false

    private var authorName: String {
        (item.comment?.author ?? item.post.author)?.nickname ?? ""
    }

    private var trimmed: String {
        text.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    var body: some View {
        CommunitySheetScaffold(title: CommunityStrings.moderationReplyTitle) {
            if !isSent {
                CommunityActionPill(
                    title: CommunityStrings.send,
                    isEnabled: !trimmed.isEmpty,
                    isLoading: isSending,
                    action: send
                )
            }
        } content: {
            if isSent {
                Text(CommunityStrings.moderationReplySent)
                    .font(theme.font(16, weight: .medium))
                    .foregroundStyle(theme.colors.textPrimary)
            } else {
                CommunityInfoBox(markdown: CommunityStrings.moderationReplyInfo(authorName))
                CommunityTextArea(
                    label: CommunityStrings.message,
                    text: $text,
                    placeholder: CommunityStrings.moderationReplyPlaceholder,
                    limit: session.config.limits.commentMaxLength
                )
                if failed { CommunityErrorLine() }
            }
        }
    }

    private func send() {
        guard !trimmed.isEmpty else { return }
        isSending = true
        failed = false
        // Under the comment when the community has replies; otherwise under the post.
        let parentId = session.config.features.repliesEnabled ? item.comment?.id : nil
        Task {
            do {
                _ = try await Factory.repository().createComment(
                    postId: item.post.id,
                    body: trimmed,
                    parentCommentId: parentId,
                    media: []
                )
                isSent = true
                try? await Task.sleep(nanoseconds: 1_200_000_000)
                dismiss()
            } catch {
                failed = true
            }
            isSending = false
        }
    }
}
