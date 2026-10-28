import XCTest
import Combine
import AppwinCore
@testable import AppwinCommunity

final class AppwinCommunityTests: XCTestCase {
    /// Push deeplinks open the post, or its replies thread.
    func testPushTargetReadsTheCommunityRoute() {
        func target(_ link: String) -> CommunityPushTarget? {
            AppwinPushPayload(deeplink: URL(string: link)!).flatMap(CommunityPushTarget.init)
        }
        XCTAssertEqual(target("appwin://community/post/p1"), CommunityPushTarget(postId: "p1"))
        XCTAssertEqual(
            target("appwin://community/post/p1/thread/c9"),
            CommunityPushTarget(postId: "p1", threadCommentId: "c9")
        )
        XCTAssertEqual(target("appwin:///community/post/p1"), CommunityPushTarget(postId: "p1"))
        XCTAssertNil(target("appwin://community"))
        XCTAssertNil(target("appwin://support/conversation/c1"))
    }

    /// Scheme and warmth are read, and a config from before them (or with a
    /// value this build does not know) keeps the light slate look.
    @MainActor
    func testThemeReadsSchemeAndWarmthWithLegacyDefaults() throws {
        func theme(_ extra: String) throws -> CommunityThemeConfig {
            let json = ##"""
            {"theme":{"primary":"#C1A6FF","primaryForeground":"#171717","fontFamily":"inter","fontScale":"default","radius":"high"\##(extra)},
             "features":{"enabled":true,"postsEnabled":true,"commentsEnabled":true,"repliesEnabled":true,"imagesEnabled":true,
               "reactionsEnabled":true,"reactions":["like"],"viewsEnabled":true,"authorEditEnabled":true,"translationEnabled":false,
               "profilesEnabled":true,"reportingEnabled":true},
             "limits":{"postMaxLength":2000,"commentMaxLength":1000,"maxImagesPerPost":4,"feedPreviewLines":6},
             "context":{"projectName":"Parkeur"},"version":3}
            """##
            return try JSONDecoder().decode(CommunityConfigDTO.self, from: Data(json.utf8)).toDomain().theme
        }

        let themed = try theme(#","colorScheme":"dark","grayWarmth":"stone""#)
        XCTAssertEqual(themed.colorScheme, .dark)
        XCTAssertEqual(themed.grayWarmth, .stone)

        let legacy = try theme("")
        XCTAssertEqual(legacy.colorScheme, .light)
        XCTAssertEqual(legacy.grayWarmth, .slate)

        let unknown = try theme(#","colorScheme":"sepia","grayWarmth":"olive""#)
        XCTAssertEqual(unknown.colorScheme, .light)
        XCTAssertEqual(unknown.grayWarmth, .slate)
    }

    /// The decoder must accept both ISO shapes the API returns: with and
    /// without fractional seconds.
    func testDateParserAcceptsBothIsoForms() {
        XCTAssertNotNil(CommunityDateParser.parse("2026-08-13T14:22:31.482Z"))
        XCTAssertNotNil(CommunityDateParser.parse("2026-08-13T14:22:31Z"))
        XCTAssertNil(CommunityDateParser.parse("pas une date"))
        XCTAssertNil(CommunityDateParser.parse(nil))
    }

    /// A `replyCount` reflects the server total, not the loaded replies: adding
    /// a reply locally must increment it, otherwise the "see N replies" label
    /// goes wrong.
    func testAppendingReplyKeepsServerTotalCoherent() {
        let root = makeComment(id: "root", replyCount: 10, replies: [])
        let updated = root.appendingReply(makeComment(id: "new", replyCount: 0, replies: []))

        XCTAssertEqual(updated.replyCount, 11)
        XCTAssertEqual(updated.replies.count, 1)
        XCTAssertEqual(updated.hiddenReplyCount, 10)
    }

    func testRemovingReplyDecrementsTotal() {
        let reply = makeComment(id: "r1", replyCount: 0, replies: [])
        let root = makeComment(id: "root", replyCount: 3, replies: [reply])

        let updated = root.removingReply(id: "r1")
        XCTAssertEqual(updated.replyCount, 2)
        XCTAssertTrue(updated.replies.isEmpty)
    }

    /// An unreadable hex colour must not make the accent transparent - parsing
    /// returns `nil` and the caller falls back to the theme.
    func testHexParsingRejectsGarbage() {
        XCTAssertNotNil(parseHexColor("#3373F2"))
        XCTAssertNotNil(parseHexColor("3373F2"))
        XCTAssertNotNil(parseHexColor("#FFF"))
        XCTAssertNil(parseHexColor("bleu"))
        XCTAssertNil(parseHexColor(""))
    }

    private func makeComment(
        id: String,
        replyCount: Int,
        replies: [CommunityComment]
    ) -> CommunityComment {
        CommunityComment(
            id: id,
            postId: "post",
            parentCommentId: nil,
            author: nil,
            body: "corps",
            media: [],
            translatedBody: nil,
            sourceLanguage: nil,
            likeCount: 0,
            replyCount: replyCount,
            myReaction: nil,
            topReactions: [],
            reactionCounts: [],
            canEdit: false,
            canDelete: false,
            isPendingReview: false,
            replies: replies,
            createdAt: Date(),
            editedAt: nil
        )
    }

    /// The contact only comes for moderators; an older API or a member viewer sends none.
    func testProfileContactIsOptional() throws {
        func profile(_ extra: String) throws -> CommunityProfile {
            let json = """
            {"id":"p1","nickname":"Alice","bio":null,"avatarUrl":null,"role":"member","isTeam":false,
             "isAnonymous":false,"postCount":1,"commentCount":0,"receivedReactionCount":0,
             "joinedAt":"2026-01-01T00:00:00.000Z","isMe":false,"isBanned":false\(extra)}
            """
            return try JSONDecoder().decode(CommunityProfileDTO.self, from: Data(json.utf8)).toDomain()
        }
        let plain = try profile("")
        XCTAssertNil(plain.email)
        XCTAssertNil(plain.externalId)
        let moderated = try profile(#","email":"a@b.co","externalId":"u-42""#)
        XCTAssertEqual(moderated.email, "a@b.co")
        XCTAssertEqual(moderated.externalId, "u-42")
    }

    func testModerationDecisionDecodes() throws {
        let json = #"{"action":"hide_content","actorName":null,"automated":true,"at":"2026-10-19T08:00:00.000Z"}"#
        let decision = try XCTUnwrap(
            JSONDecoder().decode(ModerationQueueDTO.DecisionDTO.self, from: Data(json.utf8)).toDomain()
        )
        XCTAssertEqual(decision.action, "hide_content")
        XCTAssertNil(decision.actorName)
        XCTAssertTrue(decision.automated)
    }
}

@MainActor
final class CommunityFeedPresenceTests: XCTestCase {
    override func setUp() {
        super.setUp()
        CommunityFeedPresence.reset()
        CommunityFeedPresence.mountGraceNanoseconds = 50_000_000
    }

    override func tearDown() {
        CommunityFeedPresence.reset()
        CommunityFeedPresence.mountGraceNanoseconds = 600_000_000
        super.tearDown()
    }

    /// `openPost` right after switching to a tab that was never shown: the
    /// feed mounts after the call and must take the target, not the modal.
    func testFeedMountingWithinGraceTakesTheTarget() async throws {
        var fellBack: [CommunityPushTarget] = []
        let target = CommunityPushTarget(postId: "p1", threadCommentId: "c1")
        CommunityFeedPresence.deliver(target) { fellBack.append($0) }

        let handle = CommunityFeedHandle()
        XCTAssertEqual(CommunityFeedPresence.register(handle), target)

        try await Task.sleep(nanoseconds: 150_000_000)
        XCTAssertTrue(fellBack.isEmpty)
    }

    func testNoFeedFallsBackAfterGrace() async throws {
        var fellBack: [CommunityPushTarget] = []
        let target = CommunityPushTarget(postId: "p1")
        CommunityFeedPresence.deliver(target) { fellBack.append($0) }
        XCTAssertTrue(fellBack.isEmpty)

        try await Task.sleep(nanoseconds: 150_000_000)
        XCTAssertEqual(fellBack, [target])
        XCTAssertNil(CommunityFeedPresence.register(CommunityFeedHandle()))
    }

    func testMountedFeedReceivesAtOnce() {
        let handle = CommunityFeedHandle()
        _ = CommunityFeedPresence.register(handle)
        var received: [CommunityPushTarget] = []
        let subscription = handle.targets.sink { received.append($0) }
        defer { subscription.cancel() }

        CommunityFeedPresence.deliver(CommunityPushTarget(postId: "p2")) { _ in
            XCTFail("a mounted feed must not fall back to the modal")
        }
        XCTAssertEqual(received, [CommunityPushTarget(postId: "p2")])
    }
}

final class PostDetailRefreshTests: XCTestCase {
    /// Comment events name their post in `changes`; servers from before that
    /// send none and then every comment event refetches. `post.updated` is
    /// matched on its `resourceId`.
    func testRealtimeEventsMatchTheOpenPost() {
        let created = PostDetailRealtime.commentCreated
        let deleted = PostDetailRealtime.commentDeleted
        let updated = PostDetailRealtime.postUpdated
        func concerns(_ event: String, _ payload: Any?) -> Bool {
            PostDetailRealtime.concerns(event: event, payload: payload, postId: "p1")
        }

        XCTAssertTrue(concerns(created, ["resourceId": "c1", "changes": ["p1"]]))
        XCTAssertFalse(concerns(created, ["resourceId": "c1", "changes": ["p2"]]))
        XCTAssertTrue(concerns(deleted, ["resourceId": "c1", "changes": ["p1"]]))
        XCTAssertTrue(concerns(created, ["resourceId": "c1"]))
        XCTAssertTrue(concerns(deleted, nil))

        XCTAssertTrue(concerns(updated, ["resourceId": "p1"]))
        XCTAssertTrue(concerns(updated, ["resourceId": "p1", "changes": ["body"]]))
        XCTAssertFalse(concerns(updated, ["resourceId": "p2"]))
        XCTAssertFalse(concerns(updated, ["resourceId": "p2", "changes": ["body"]]))
    }

    /// A burst of events costs one refetch, after the last one.
    @MainActor
    func testDebouncerCoalescesABurst() async throws {
        let debouncer = RefreshDebouncer(delay: 0.05)
        var calls = 0
        for _ in 0..<5 { debouncer.schedule { calls += 1 } }
        try await Task.sleep(nanoseconds: 300_000_000)
        XCTAssertEqual(calls, 1)

        debouncer.schedule { calls += 1 }
        debouncer.cancel()
        try await Task.sleep(nanoseconds: 150_000_000)
        XCTAssertEqual(calls, 1)
    }

    func testSanctionTypesAreRecognised() async {
        let sanctions: [CommunityNotificationType] = [.contentRemoved, .accountWarned, .accountBanned]
        let others: [CommunityNotificationType] = [.postComment, .commentReply, .postReaction, .adminPost]
        await MainActor.run {
            XCTAssertTrue(sanctions.allSatisfy(CommunityInAppWatcher.isSanction))
            XCTAssertFalse(others.contains(where: CommunityInAppWatcher.isSanction))
        }
    }
}
