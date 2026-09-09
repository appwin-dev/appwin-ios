import Foundation
#if os(iOS) && canImport(AppTrackingTransparency) && canImport(AdSupport)
import AdSupport
import AppTrackingTransparency
#endif

/// Reports the device advertising identifier (IDFA) to the ad-identity
/// endpoint (ADR-0038, S2S activation), strictly under the advertising
/// consent AND an authorized ATT status. The identifier never rides the
/// analytics event stream: the event ingest is zero-PII by contract,
/// this is its own channel with its own lifecycle - consent revoked (or
/// ATT withdrawn in Settings) means a DELETE, server-side row gone.
///
/// Best effort by design: a missing or zeroed IDFA and network failures
/// degrade to "no identifier", which only lowers the match rate of the
/// future CAPI forwarding.
actor AdIdentityReporter {
  /// `id` is nil whenever the OS will not hand out a usable IDFA
  /// (ATT not authorized, zeroed identifier).
  struct IdfaInfo: Sendable {
    let id: String?
    let attStatus: String
  }

  private let prefs: AnalyticsPrefs
  private let keyPrefix: String
  private let client: @Sendable () -> ClientApi?
  private let reauthorize: @Sendable () async -> Bool
  /// Seam for tests; production reads ATT + AdSupport.
  private let idfaProvider: @Sendable () -> IdfaInfo?

  init(
    prefs: AnalyticsPrefs,
    keyPrefix: String,
    client: @escaping @Sendable () -> ClientApi?,
    reauthorize: @escaping @Sendable () async -> Bool,
    idfaProvider: @escaping @Sendable () -> IdfaInfo? = systemIdfa
  ) {
    self.prefs = prefs
    self.keyPrefix = keyPrefix
    self.client = client
    self.reauthorize = reauthorize
    self.idfaProvider = idfaProvider
  }

  var consent: AdvertisingConsent {
    Self.storedConsent(prefs: prefs, keyPrefix: keyPrefix)
  }

  /// Shared with the ad-signals hub, which needs a synchronous read the
  /// actor isolation would otherwise forbid.
  static func storedConsent(prefs: AnalyticsPrefs, keyPrefix: String) -> AdvertisingConsent {
    switch prefs.string(forKey: keyPrefix + consentKey) {
    case "granted": .granted
    case "denied": .denied
    default: .unknown
    }
  }

  func setConsent(_ consent: AdvertisingConsent) async {
    let stored: String? =
      switch consent {
      case .granted: "granted"
      case .denied: "denied"
      case .unknown: nil
      }
    prefs.set(stored, forKey: keyPrefix + Self.consentKey)
    switch consent {
    case .granted:
      await sync()
    // `unknown` also revokes anything already sent: without a standing
    // `granted` the server must not keep an identifier.
    case .denied, .unknown:
      await deleteRemote()
    }
  }

  /// Called at product start and after an ATT answer: the retry path.
  func start() async {
    guard consent == .granted else { return }
    await sync()
  }

  private struct Body: Encodable {
    let platform = "ios"
    let adId: String?
    let attStatus: String

    /// The wire contract wants an explicit `adId: null`, not an absent
    /// key: encode the nil by hand.
    func encode(to encoder: Encoder) throws {
      var container = encoder.container(keyedBy: CodingKeys.self)
      try container.encode(platform, forKey: .platform)
      try container.encode(adId, forKey: .adId)
      try container.encode(attStatus, forKey: .attStatus)
    }

    private enum CodingKeys: String, CodingKey {
      case platform, adId, attStatus
    }
  }

  private func sync() async {
    guard consent == .granted else { return }
    guard let info = idfaProvider() else { return }
    // No usable IDFA (ATT refused, zeroed) still reports with a null id:
    // the row marks the consent, so the CAPI connector forwards the
    // events - just without the identifier.
    var id = info.id?.lowercased()
    if id?.isEmpty == true || id == Self.zeroedIdfa { id = nil }
    let marker = id ?? Self.noIdMarker
    guard prefs.string(forKey: keyPrefix + Self.sentKey) != marker else { return }
    let body = Body(adId: id, attStatus: info.attStatus)
    if await send({ try await $0.requestVoid(path: Self.endpoint, httpMethod: .put, body: body) }) {
      prefs.set(marker, forKey: keyPrefix + Self.sentKey)
    }
  }

  private func deleteRemote() async {
    guard prefs.string(forKey: keyPrefix + Self.sentKey) != nil else { return }
    if await send({ try await $0.requestVoid(path: Self.endpoint, httpMethod: .delete) }) {
      prefs.set(nil, forKey: keyPrefix + Self.sentKey)
    }
  }

  /// One 401-reauthorize retry, mirroring the event pipeline's policy.
  private func send(_ block: @Sendable (ClientApi) async throws -> Void) async -> Bool {
    guard let api = client() else { return false }
    for attempt in 0..<2 {
      do {
        try await block(api)
        return true
      } catch AppwinApiError.http(let status) where status == 401 && attempt == 0 {
        guard await reauthorize() else { return false }
      } catch {
        return false
      }
    }
    return false
  }

  private static let endpoint = "/api/sdk/v1/attribution/ad-identity"
  static let consentKey = "advertising.consent"
  private static let sentKey = "adid.sent"
  private static let zeroedIdfa = "00000000-0000-0000-0000-000000000000"
  /// Sent-state marker for the "consent yes, identifier no" report.
  private static let noIdMarker = "-"

  static let systemIdfa: @Sendable () -> IdfaInfo? = {
    #if os(iOS) && canImport(AppTrackingTransparency) && canImport(AdSupport)
    let status = ATTrackingManager.trackingAuthorizationStatus
    let attStatus =
      switch status {
      case .authorized: "authorized"
      case .denied: "denied"
      case .restricted: "restricted"
      default: "notDetermined"
      }
    guard status == .authorized else { return IdfaInfo(id: nil, attStatus: attStatus) }
    return IdfaInfo(
      id: ASIdentifierManager.shared().advertisingIdentifier.uuidString,
      attStatus: attStatus)
    #else
    return nil
    #endif
  }
}
