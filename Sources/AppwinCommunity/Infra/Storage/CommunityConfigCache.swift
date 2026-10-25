import Foundation

/// Cache disque du body brut de `/config`.
///
/// The JSON is stored as-is rather than the decoded config: the next launch
/// replays exactly the same decode as the network, so a DTO change never has to
/// handle an older cache format. An unreadable cache is simply ignored.
///
/// `UserDefaults` rather than the keychain: nothing in here is secret, and the
/// cache is meant to disappear with the app.
enum CommunityConfigCache {
    private static func key(appId: String) -> String {
        "appwin.community.config.\(appId)"
    }

    static func read(appId: String) -> Data? {
        UserDefaults.standard.data(forKey: key(appId: appId))
    }

    static func write(_ data: Data, appId: String) {
        UserDefaults.standard.set(data, forKey: key(appId: appId))
    }

    static func clear(appId: String) {
        UserDefaults.standard.removeObject(forKey: key(appId: appId))
    }
}
