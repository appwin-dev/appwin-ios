import SwiftUI
import UIKit
import AppwinCore

@MainActor
enum CommunityPostLookup {
    /// A post by id, wherever it sits in the feed.
    ///
    /// Falls back to the first all-groups page when the API predates
    /// `GET posts/:id`: recent posts, which is what a push points at, still open.
    static func find(postId: String) async -> CommunityPost? {
        let repo = Factory.repository()
        if let post = try? await repo.post(postId: postId) { return post }
        let page = try? await repo.feed(
            groupId: nil,
            authorProfileId: nil,
            sort: .recent,
            cursor: nil,
            limit: CommunityPagination.feedPageSize
        )
        return page?.items.first { $0.id == postId }
    }
}

/// A post (and its reply thread) presented over the host app, for a push tap
/// or `openPost` when no feed is mounted to open it in.
struct CommunityPostModalView: View {
    let target: CommunityPushTarget
    let onClose: () -> Void

    @StateObject private var session: CommunitySession
    @State private var post: CommunityPost?
    @State private var notFound = false
    @State private var path = NavigationPath()

    init(target: CommunityPushTarget, onClose: @escaping () -> Void) {
        self.target = target
        self.onClose = onClose
        let session = Factory.makeSession()
        session.loadCache()
        _session = StateObject(wrappedValue: session)
    }

    var body: some View {
        let theme = CommunityTheme(config: session.config)
        NavigationStack(path: $path) {
            content(theme)
                .toolbar {
                    ToolbarItem(placement: .topBarLeading) {
                        Button(action: onClose) {
                            Image(systemName: "xmark")
                                .font(.system(size: 15, weight: .semibold))
                                .foregroundStyle(theme.colors.textPrimary)
                        }
                        .accessibilityLabel(CommunityStrings.close)
                    }
                }
                .navigationDestination(for: ReplyThreadRoute.self) { route in
                    ReplyThreadDeepLinkHost(
                        postId: route.postId,
                        rootCommentId: route.rootCommentId,
                        fromPushDeeplink: route.fromPushDeeplink
                    )
                    .environmentObject(session)
                }
        }
        .environmentObject(session)
        .communityTheme(theme)
        .preferredColorScheme(.light)
        .task { await load() }
    }

    @ViewBuilder
    private func content(_ theme: CommunityTheme) -> some View {
        if let post {
            PostDetailView(
                post: post,
                onCommentCountChange: { _ in },
                onDeleted: onClose,
                onOpenThread: { threadId in
                    path.append(ReplyThreadRoute(postId: post.id, rootCommentId: threadId))
                }
            )
        } else if notFound {
            CommunityEmptyState(
                systemImage: "exclamationmark.triangle",
                title: CommunityStrings.loadErrorTitle,
                message: CommunityStrings.loadErrorMessage,
                actionTitle: CommunityStrings.retry,
                expandsToFill: true,
                action: { Task { await load() } }
            )
            .background(theme.colors.background)
        } else {
            ProgressView()
                .tint(theme.colors.accent)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(theme.colors.background)
        }
    }

    private func load() async {
        notFound = false
        async let bootstrap: Void = session.bootstrap()
        let found = await CommunityPostLookup.find(postId: target.postId)
        await bootstrap
        guard let found else {
            notFound = true
            return
        }
        post = found
        if let threadId = target.threadCommentId, path.isEmpty {
            path.append(
                ReplyThreadRoute(postId: found.id, rootCommentId: threadId, fromPushDeeplink: true)
            )
        }
    }

    static func present(_ target: CommunityPushTarget) {
        guard let presenter = AppwinCommunity.topViewController() else { return }
        var host: UIHostingController<CommunityPostModalView>?
        let controller = UIHostingController(
            rootView: CommunityPostModalView(target: target) { host?.dismiss(animated: true) }
        )
        host = controller
        controller.modalPresentationStyle = .pageSheet
        presenter.present(controller, animated: true)
    }
}
