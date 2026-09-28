import Testing
@testable import AppwinSupport
import AppwinCore

/// `@MainActor` because the SDK is: `AppwinSupport` is MainActor-isolated, and
/// under strict concurrency the assertion cannot read its state from a
/// non-isolated context.
@MainActor
@Test func versionIsSet() async throws {
    #expect(!AppwinSupport.version.isEmpty)
}

@Test func supportPushResolvesItsConversation() {
    let conversation = { (data: [AnyHashable: Any]) in
        AppwinPushPayload(data).flatMap(SupportPushHandler.conversationId(of:))
    }
    #expect(conversation(["appwinType": "support.message", "deeplink": "appwin://support/conversation/c1"]) == "c1")
    #expect(conversation(["deeplink": "appwin:///support/conversation/c2"]) == "c2")
    #expect(conversation(["appwinType": "support.message"]) == nil)
    #expect(conversation(["deeplink": "appwin://community/post/p1"]) == nil)
}
