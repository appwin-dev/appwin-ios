// Dashboard-driven feature flags, following Intercom's `modules` model.
// Pure boolean kill switches; copy such as the greeting has no place here.
// Domain mirror of `SdkModules` (packages/contracts).

import Foundation

struct SdkModules: Equatable {
    /// Is the FAQ section shown? A kill switch: `false` shows nothing and does
    /// not even fetch the FAQs, saving a network call.
    let faqEnabled: Bool

    /// Safe default: everything on. Do not hide an existing feature just
    /// because no config has arrived yet (offline, first launch).
    static let defaults = SdkModules(faqEnabled: true)
}
