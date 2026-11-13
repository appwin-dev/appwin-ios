import CoreText
import Foundation
import UIKit

/// Turns the font name the studio typed into a name UIKit can open.
///
/// A native app bundles its fonts and lists them under `UIAppFonts`: the name
/// resolves as is. A Flutter app declares them in `pubspec.yaml` only, which
/// registers them in Flutter's engine and nowhere else, so `UIFont(name:)`
/// cannot see them. Flutter still ships the files, with a manifest, inside
/// `App.framework/flutter_assets`: the matching file is registered here for
/// the process, and its PostScript name returned.
enum CommunityFontResolver {
    private static let cache = ResolvedFonts()

    static func resolve(_ name: String) -> String? {
        if let known = cache.get(name) { return known.value }
        let resolved = UIFont(name: name, size: 12) != nil ? name : registerFlutterFont(named: name)
        cache.set(name, resolved)
        return resolved
    }

    private static func registerFlutterFont(named name: String) -> String? {
        guard let assets = flutterAssetsURL(),
              let data = try? Data(contentsOf: assets.appendingPathComponent("FontManifest.json")),
              let families = try? JSONDecoder().decode([FontManifestFamily].self, from: data)
        else { return nil }

        // The studio asks for a PostScript name, usually the file name; the
        // Flutter family name is accepted too, it is what a Flutter dev knows.
        let paths = families.flatMap { family in
            family.family == name
                ? Array(family.fonts.prefix(1))
                : family.fonts.filter { fileStem($0.asset) == name }
        }.map(\.asset)

        for path in paths {
            let url = assets.appendingPathComponent(path)
            // Already registered by an earlier lookup: the error is harmless,
            // the descriptor below still names the font.
            CTFontManagerRegisterFontsForURL(url as CFURL, .process, nil)
            guard let descriptors = CTFontManagerCreateFontDescriptorsFromURL(url as CFURL)
                    as? [CTFontDescriptor],
                  let first = descriptors.first,
                  let postScript = CTFontDescriptorCopyAttribute(first, kCTFontNameAttribute) as? String,
                  UIFont(name: postScript, size: 12) != nil
            else { continue }
            return postScript
        }
        return nil
    }

    private static func flutterAssetsURL() -> URL? {
        let url = Bundle.main.bundleURL
            .appendingPathComponent("Frameworks/App.framework/flutter_assets", isDirectory: true)
        return FileManager.default.fileExists(atPath: url.path) ? url : nil
    }

    private static func fileStem(_ path: String) -> String {
        ((path as NSString).lastPathComponent as NSString).deletingPathExtension
    }
}

private struct FontManifestFamily: Decodable {
    struct Entry: Decodable { let asset: String }
    let family: String
    let fonts: [Entry]
}

/// Lookups read the app bundle: once per name for the process.
private final class ResolvedFonts: @unchecked Sendable {
    struct Entry { let value: String? }

    private let lock = NSLock()
    private var entries: [String: Entry] = [:]

    func get(_ name: String) -> Entry? {
        lock.lock()
        defer { lock.unlock() }
        return entries[name]
    }

    func set(_ name: String, _ value: String?) {
        lock.lock()
        defer { lock.unlock() }
        entries[name] = Entry(value: value)
    }
}
