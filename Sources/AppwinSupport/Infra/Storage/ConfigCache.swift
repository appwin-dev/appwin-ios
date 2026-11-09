import Foundation

/// Local cache of the messenger config: the raw JSON the API returned,
/// `version` included. Keyed by `appId`, since one app id is one project and so
/// one config, which stops an app change from serving the previous config.
enum ConfigCache {
    private static func key(_ appId: String) -> String {
        "appwin.config.\(appId)"
    }

    static func read(appId: String) -> Data? {
        UserDefaults.standard.data(forKey: key(appId))
    }

    static func write(_ data: Data, appId: String) {
        UserDefaults.standard.set(data, forKey: key(appId))
    }
}
