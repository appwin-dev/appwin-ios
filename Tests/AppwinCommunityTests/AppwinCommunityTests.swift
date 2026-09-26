import XCTest
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
}
