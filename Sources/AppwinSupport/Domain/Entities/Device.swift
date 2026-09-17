// Miroir du contrat serveur `device.schema.ts` (cf. svc-support-erd.mmd).
// A device attached to a customer. A customer owns several;
// `Customer.latestDevice` exposes the most recent.
public struct Device: Codable, Sendable {
    public let id: String
    public let orgId: String
    public let projectId: String
    public let customerId: String
    public let deviceId: String
    public let platform: String?   // "mobile" | "web"
    public let model: String?      // ex. "iPhone15,2"
    public let os: String?
    public let appVersion: String?
    public let sdkVersion: String?
    public let location: String?
    public let lastSeenAt: String?
    public let createdAt: String
    public let updatedAt: String
}
