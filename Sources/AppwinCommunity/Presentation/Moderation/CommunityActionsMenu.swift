import SwiftUI

/// The « ⋯ » of a post, a comment or a profile (Figma 178:2735), opening its
/// menu right there: members edit, delete or report; moderators and admins
/// also move, pin, hide, delete with a motif, and sanction members.
///
/// Needs `communityContentActions` on the screen, which runs the actions.
struct CommunityActionsMenu<Label: View>: View {
    let target: CommunityActionTarget
    @ViewBuilder var label: () -> Label

    @EnvironmentObject private var session: CommunitySession
    @EnvironmentObject private var controller: CommunityActionsController

    var body: some View {
        Menu {
            switch target {
            case .post(let post): postItems(post)
            case .comment(let comment): commentItems(comment)
            case .member(let author): memberItems(author)
            }
        } label: {
            label()
        }
    }

    @ViewBuilder
    private func postItems(_ post: CommunityPost) -> some View {
        let moderates = canModerate(post.author)
        if post.canEdit, controller.canEdit {
            Button(CommunityStrings.edit) { controller.edit(post) }
        }
        if session.profile.canModerate {
            if session.groups.count > 1 {
                Button(CommunityStrings.moveToGroup) { controller.sheet = .group(post) }
            }
            if post.isPinned {
                Button(CommunityStrings.unpinAction) { controller.unpin(post) }
            } else {
                Button(CommunityStrings.pinAction) { controller.sheet = .pin(post) }
            }
        }
        if moderates {
            Button(CommunityStrings.hide) { controller.sheet = .reason(.hide, .post(post)) }
            Button(CommunityStrings.delete, role: .destructive) {
                controller.sheet = .reason(.remove, .post(post))
            }
        } else if post.canDelete {
            Button(CommunityStrings.delete, role: .destructive) { controller.pendingDeletion = .post(post) }
        }
        if !post.canEdit, !moderates, session.config.features.reportingEnabled {
            Button(CommunityStrings.report) {
                controller.sheet = .report(ReportTarget(type: "post", id: post.id))
            }
        }
    }

    @ViewBuilder
    private func commentItems(_ comment: CommunityComment) -> some View {
        let moderates = canModerate(comment.author)
        if moderates {
            Button(CommunityStrings.hide) { controller.sheet = .reason(.hide, .comment(comment)) }
            Button(CommunityStrings.delete, role: .destructive) {
                controller.sheet = .reason(.remove, .comment(comment))
            }
        } else if comment.canDelete {
            Button(CommunityStrings.delete, role: .destructive) { controller.pendingDeletion = .comment(comment) }
        }
        if !comment.canEdit, !moderates, session.config.features.reportingEnabled {
            Button(CommunityStrings.report) {
                controller.sheet = .report(ReportTarget(type: "comment", id: comment.id))
            }
        }
    }

    @ViewBuilder
    private func memberItems(_ author: CommunityAuthor) -> some View {
        if canModerate(author) {
            Button(CommunityStrings.warnAction) { controller.sheet = .sanction(.warn, author) }
            Button(CommunityStrings.shadowBanAction) { controller.sheet = .sanction(.shadowBan, author) }
            Button(CommunityStrings.banAction, role: .destructive) { controller.sheet = .sanction(.ban, author) }
        } else if session.config.features.reportingEnabled {
            Button(CommunityStrings.report) {
                controller.sheet = .report(ReportTarget(type: "profile", id: author.id))
            }
        }
    }

    /// Same rule as the API: never oneself nor an admin; a moderator only by an admin.
    private func canModerate(_ author: CommunityAuthor?) -> Bool {
        let me = session.profile
        guard me.canModerate, let author, author.isAddressable, author.id != me.id else { return false }
        switch author.role {
        case .member: return true
        case .moderator: return me.role == .admin
        case .admin: return false
        }
    }
}
