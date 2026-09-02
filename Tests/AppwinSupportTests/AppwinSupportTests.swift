import Testing
@testable import AppwinSupport

/// `@MainActor` because the SDK is: `AppwinSupport` is MainActor-isolated, and
/// under strict concurrency the assertion cannot read its state from a
/// non-isolated context.
@MainActor
@Test func versionIsSet() async throws {
    #expect(!AppwinSupport.version.isEmpty)
}
