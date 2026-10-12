// The SDK's session store, a shared source of truth.
//
// Store-centric rather than one ViewModel per screen: a single AppwinSession
// lives as long as the messenger is open, holds the global state (signed-in
// customer, network client) and orchestrates it. Views observe it directly.
//
// Views never touch `ClientApi`: they go through the store, which owns it.

import Foundation
import Combine
import AppwinCore

@MainActor
final class AppwinSession: ObservableObject {
    /// Current customer, lead or identified.
    @Published private(set) var customer: Customer?

    /// Network client, already configured with the identity headers.
    let client: ClientApi

    init(customer: Customer?, client: ClientApi) {
        self.customer = customer
        self.client = client
    }

    /// Updates the customer, after an identify or an update. Only the session
    /// writes, hence the `private(set)` above.
    func setCustomer(_ customer: Customer) {
        self.customer = customer
    }
}
