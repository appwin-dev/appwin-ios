import SwiftUI

/// What the « ⋯ » menu acts on.
enum CommunityActionTarget: Identifiable {
    case post(CommunityPost)
    case comment(CommunityComment)
    case member(CommunityAuthor)

    var id: String {
        switch self {
        case .post(let post): return "post:\(post.id)"
        case .comment(let comment): return "comment:\(comment.id)"
        case .member(let author): return "member:\(author.id)"
        }
    }
}

/// How the screen showing the content follows up on an action.
struct CommunityActionHandlers {
    var onEdit: ((CommunityPost) -> Void)?
    /// Deleted by its author, hidden or removed by a moderator: gone from this screen.
    var onPostGone: (String) -> Void = { _ in }
    /// Moved or (un)pinned: the fresh post from the server.
    var onPostUpdated: (CommunityPost) -> Void = { _ in }
    var onCommentGone: (CommunityComment) -> Void = { _ in }
}

/// Sheets an action opens.
enum CommunityActionSheet: Identifiable {
    case report(ReportTarget)
    case reason(ModerationReasonSheet.Kind, CommunityActionTarget)
    case group(CommunityPost)
    case pin(CommunityPost)
    case sanction(MemberSanctionSheet.Kind, CommunityAuthor)

    var id: String {
        switch self {
        case .report(let target): return "report:\(target.id)"
        case .reason(let kind, let target): return "reason:\(kind):\(target.id)"
        case .group(let post): return "group:\(post.id)"
        case .pin(let post): return "pin:\(post.id)"
        case .sanction(let kind, let author): return "sanction:\(kind):\(author.id)"
        }
    }
}

/// One per screen: the `CommunityActionsMenu`s of its posts, comments and
/// profile open sheets and run actions through it.
@MainActor
final class CommunityActionsController: ObservableObject {
    @Published var sheet: CommunityActionSheet?
    @Published var pendingDeletion: CommunityActionTarget?
    var handlers = CommunityActionHandlers()

    func edit(_ post: CommunityPost) {
        handlers.onEdit?(post)
    }

    var canEdit: Bool { handlers.onEdit != nil }

    func decide(_ action: ModerationAction, on target: CommunityActionTarget, reason: ModerationReason) async throws {
        let (type, id): (ModerationTargetType, String)
        switch target {
        case .post(let post): (type, id) = (.post, post.id)
        case .comment(let comment): (type, id) = (.comment, comment.id)
        case .member: return
        }
        try await Factory.moderationRepository().decide(
            targetType: type,
            targetId: id,
            action: action,
            reason: reason.rawValue,
            durationHours: nil,
            reportIds: []
        )
        switch target {
        case .post(let post): handlers.onPostGone(post.id)
        case .comment(let comment): handlers.onCommentGone(comment)
        case .member: break
        }
    }

    func confirmDeletion() {
        guard let target = pendingDeletion else { return }
        pendingDeletion = nil
        Task {
            // Optimistic: a post that stays after tapping Delete is more confusing
            // than one that comes back on the next refresh.
            switch target {
            case .post(let post):
                handlers.onPostGone(post.id)
                try? await Factory.repository().deletePost(postId: post.id)
            case .comment(let comment):
                handlers.onCommentGone(comment)
                try? await Factory.repository().deleteComment(commentId: comment.id)
            case .member:
                break
            }
        }
    }

    func unpin(_ post: CommunityPost) {
        Task {
            try? await Factory.moderationRepository().unpin(postId: post.id)
            await refresh(post)
        }
    }

    func refresh(_ post: CommunityPost) async {
        if let fresh = try? await Factory.repository().post(postId: post.id) {
            handlers.onPostUpdated(fresh)
        }
    }
}

extension View {
    /// Gives the screen's `CommunityActionsMenu`s their controller, and presents
    /// what they open: the sheets and the delete confirmation.
    func communityContentActions(_ handlers: CommunityActionHandlers) -> some View {
        modifier(CommunityContentActions(handlers: handlers))
    }
}

private struct CommunityContentActions: ViewModifier {
    let handlers: CommunityActionHandlers

    @EnvironmentObject private var session: CommunitySession
    @StateObject private var controller = CommunityActionsController()

    func body(content: Content) -> some View {
        content
            .environmentObject(controller)
            .onAppear { controller.handlers = handlers }
            // An alert, not a confirmation dialog: iOS 26 anchors those to the
            // whole screen, far from the « ⋯ » that opened them.
            .alert(
                deletionTitle,
                isPresented: Binding(
                    get: { controller.pendingDeletion != nil },
                    set: { if !$0 { controller.pendingDeletion = nil } }
                )
            ) {
                Button(CommunityStrings.delete, role: .destructive) { controller.confirmDeletion() }
                Button(CommunityStrings.cancel, role: .cancel) {}
            } message: {
                if case .post = controller.pendingDeletion {
                    Text(CommunityStrings.deletePostMessage)
                }
            }
            .sheet(item: $controller.sheet) { sheet in
                sheetView(sheet).environmentObject(session)
            }
    }

    private var deletionTitle: String {
        if case .comment = controller.pendingDeletion { return CommunityStrings.deleteCommentTitle }
        return CommunityStrings.deletePostTitle
    }

    @ViewBuilder
    private func sheetView(_ sheet: CommunityActionSheet) -> some View {
        switch sheet {
        case .report(let target):
            ReportSheet(target: target)
        case .reason(let kind, let target):
            ModerationReasonSheet(kind: kind, authorName: authorName(of: target)) { reason in
                try await controller.decide(kind == .remove ? .removeContent : .hideContent, on: target, reason: reason)
            }
        case .group(let post):
            GroupPickerSheet(groups: session.groups, currentGroupId: post.groupId) { groupId in
                try await Factory.moderationRepository().moveToGroup(postId: post.id, groupId: groupId)
                await controller.refresh(post)
            }
        case .pin(let post):
            PinSettingsSheet { settings in
                try await Factory.moderationRepository().pin(postId: post.id, settings: settings)
                await controller.refresh(post)
            }
        case .sanction(let kind, let author):
            MemberSanctionSheet(kind: kind, member: author)
        }
    }

    private func authorName(of target: CommunityActionTarget) -> String {
        switch target {
        case .post(let post): return post.author?.nickname ?? ""
        case .comment(let comment): return comment.author?.nickname ?? ""
        case .member(let author): return author.nickname
        }
    }
}
