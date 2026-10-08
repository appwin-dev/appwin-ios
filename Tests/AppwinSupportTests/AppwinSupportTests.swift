import Foundation
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

@MainActor
@Test func designReadsSchemeAndWarmthAndDefaultsOlderConfigs() throws {
    func design(_ json: String) throws -> MessengerDesign {
        let body = ##"{"colors":{"primary":"#C1A6FF","primaryForeground":"#171717"},"version":3,"design":"## + json + "}"
        return try JSONDecoder().decode(MessengerConfigDTO.self, from: Data(body.utf8)).toDomain().design
    }

    let themed = try design(#"{"colorScheme":"dark","grayWarmth":"stone","radius":"max"}"#)
    #expect(themed.colorScheme == .dark)
    #expect(themed.grayWarmth == .stone)
    #expect(themed.radius == .max)

    // A config cached before these fields existed keeps the light slate look.
    let legacy = try design(#"{"radius":"low"}"#)
    #expect(legacy.colorScheme == .light)
    #expect(legacy.grayWarmth == .slate)

    // An unknown value (newer server) degrades instead of failing the decode.
    let unknown = try design(#"{"colorScheme":"sepia","grayWarmth":"olive"}"#)
    #expect(unknown.colorScheme == .light)
    #expect(unknown.grayWarmth == .slate)
}

#if DEBUG
@Test func debugDiagnosisNamesEachVerdictAsTheSdkLogsIt() {
    #expect(SupportDebugDiagnosis(result: nil)?.code == "notInitialized")
    #expect(SupportDebugDiagnosis(result: .notConfigured)?.code == "notConfigured")
    #expect(SupportDebugDiagnosis(result: .unknown)?.code == "unknown")
    #expect(SupportDebugDiagnosis(result: .unavailable(.plan))?.code == "unavailable(plan)")
    #expect(SupportDebugDiagnosis(result: .unavailable(.disabled))?.code == "unavailable(disabled)")
    #expect(SupportDebugDiagnosis(result: .ready) == nil)
}

@Test func debugDiagnosisPointsAPlanRefusalAtPricing() {
    let pricing = URL(string: "https://appwin.io/pricing")!
    #expect(SupportDebugDiagnosis(result: .unavailable(.plan))?.actionUrl == pricing)
    #expect(SupportDebugDiagnosis.debugUnlocked.actionUrl == pricing)
}
#endif
