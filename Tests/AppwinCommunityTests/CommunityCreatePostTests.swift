import XCTest
import AppwinCore
@testable import AppwinCommunity

/// `createPost` refuses what the server would refuse, before any request.
final class CommunityCreatePostTests: XCTestCase {
    @MainActor
    func testBlankTextIsRefusedBeforeAnyRequest() async {
        await assertInvalidArgument("text is empty") {
            _ = try await AppwinCommunity.createPost(text: "  \n ")
        }
    }

    @MainActor
    func testMoreThanTenImagesIsRefusedBeforeAnyRequest() async {
        await assertInvalidArgument("11 images") {
            _ = try await AppwinCommunity.createPost(
                text: "Super séance",
                images: Array(repeating: Data([0]), count: 11)
            )
        }
    }

    @MainActor
    private func assertInvalidArgument(
        _ fragment: String,
        _ body: () async throws -> Void,
        line: UInt = #line
    ) async {
        do {
            try await body()
            XCTFail("expected invalidArgument", line: line)
        } catch AppwinCommunityError.invalidArgument(let detail) {
            XCTAssertTrue(detail.contains(fragment), detail, line: line)
        } catch {
            XCTFail("unexpected \(error)", line: line)
        }
    }
}
