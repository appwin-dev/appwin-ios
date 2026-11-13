// Miroir du contrat serveur `customer.schema.ts` (cf. svc-support-erd.mmd).
// The person's identity only. Device traits live on `Device`, exposed here
// through `latestDevice`, the most recently seen one.
public struct Customer: Codable, Sendable {
    public let id: String
    public let orgId: String
    public let projectId: String
    public let externalId: String?
    public let email: String?
    public let name: String?
    public let avatarUrl: String?
    public let language: String?
    public let timezone: String?
    public let plan: String?
    public let type: String  // "user" | "lead"
    public let firstSeenAt: String?
    public let lastSeenAt: String?
    public let sessions: Int
    public let createdAt: String
    public let updatedAt: String
    public let latestDevice: Device?
}
