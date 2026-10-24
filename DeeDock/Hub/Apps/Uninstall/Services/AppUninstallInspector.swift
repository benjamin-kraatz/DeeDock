import CoreServices
import Foundation
import Security

/// Reads what an app is before it's uninstalled: identity, signature, embedded bundles, and where it
/// came from. Synchronous and file-system bound; call it off the main actor.
nonisolated enum AppUninstallInspector {
    /// Folders inside a bundle that hold embedded bundles with identifiers of their own, and the
    /// extensions those bundles use.
    private static let embeddedFolders: [(path: String, extensions: Set<String>)] = [
        ("Contents/PlugIns", ["appex"]), ("Contents/Extensions", ["appex"]), ("Contents/Library/LoginItems", ["app"]),
        ("Contents/Library/SystemExtensions", ["systemextension"]), ("Contents/XPCServices", ["xpc"]),
        ("Contents/Helpers", ["app"]), ("Contents/Frameworks", ["app"]),
    ]

    /// Inspects the app at `url`.
    /// - Parameters:
    ///   - url: The app bundle.
    ///   - name: The name DOKK already shows for it.
    static func inspect(_ url: URL, name: String) -> AppUninstallTarget {
        let url = url.standardizedFileURL
        let bundle = Bundle(url: url)
        let info = bundle?.infoDictionary ?? [:]
        let signing = signingInfo(url)
        var groups = signing.groups
        var embeddedIdentifiers: [String] = []
        var hasSystemExtensions = false
        for item in embeddedBundles(in: url) {
            if item.pathExtension == "systemextension" { hasSystemExtensions = true }
            if let identifier = Bundle(url: item)?.bundleIdentifier { embeddedIdentifiers.append(identifier) }
            groups += signingInfo(item).groups
        }
        let owner = (try? FileManager.default.attributesOfItem(atPath: url.path))?[.ownerAccountID] as? NSNumber
        let ownedByRoot = owner?.intValue == 0
        let metadata = MDItemCreateWithURL(kCFAllocatorDefault, url as CFURL)
        let source: AppUninstallSource
        if FileManager.default.fileExists(atPath: url.appendingPathComponent("Contents/_MASReceipt/receipt").path) {
            source = attribute(metadata, "kMDItemAppStoreReceiptType") as? String == "ProductionSandbox" ? .testFlight : .appStore
        } else {
            source = ownedByRoot ? .installer : .downloaded
        }
        // Space on disk, like the data rows: APFS compression makes an app's logical size much larger.
        let size = (attribute(metadata, "kMDItemPhysicalSize") as? NSNumber ?? attribute(metadata, "kMDItemLogicalSize") as? NSNumber)?.int64Value
        let names = [name, info["CFBundleDisplayName"] as? String, info["CFBundleName"] as? String,
                     info["CFBundleExecutable"] as? String, url.deletingPathExtension().lastPathComponent].compactMap { $0 }
        return AppUninstallTarget(
            url: url, name: name, bundleIdentifier: bundle?.bundleIdentifier,
            version: info["CFBundleShortVersionString"] as? String, source: source, ownedByRoot: ownedByRoot,
            teamIdentifier: signing.team, appGroups: groups, embeddedIdentifiers: embeddedIdentifiers,
            helperIdentifiers: helperIdentifiers(in: url, info: info), names: names,
            hasSystemExtensions: hasSystemExtensions, vendorUninstaller: vendorUninstaller(for: url, names: names),
            byteCount: size)
    }

    /// Other bundles on this Mac with `identifier`, besides `url`: copies that share the app's data.
    ///
    /// The Launcher keeps one copy per bundle identifier, so its list can't answer this. Spotlight finds
    /// copies anywhere; the Applications folders are also read directly (two levels deep) in case Spotlight
    /// is off. Copies in a Trash and bundles nested inside other bundles don't count.
    static func otherCopies(of identifier: String, excluding url: URL, home: URL) -> [URL] {
        var paths = Set<String>()
        // The identifier goes inside a query string; one that could break out of the quotes is skipped.
        if !identifier.contains("'"), !identifier.contains("\\"), !identifier.contains("*"),
           let query = MDQueryCreate(kCFAllocatorDefault, "kMDItemCFBundleIdentifier == '\(identifier)'" as CFString, nil, nil),
           MDQueryExecute(query, CFOptionFlags(kMDQuerySynchronous.rawValue)) {
            for index in 0..<MDQueryGetResultCount(query) {
                guard let raw = MDQueryGetResultAtIndex(query, index) else { continue }
                let item = Unmanaged<MDItem>.fromOpaque(raw).takeUnretainedValue()
                if let path = MDItemCopyAttribute(item, kMDItemPath) as? String { paths.insert(path) }
            }
        }
        for root in [URL(fileURLWithPath: "/Applications"), home.appendingPathComponent("Applications")] {
            let top = (try? FileManager.default.contentsOfDirectory(at: root, includingPropertiesForKeys: nil)) ?? []
            let candidates = top + top.filter { $0.pathExtension != "app" }.flatMap {
                (try? FileManager.default.contentsOfDirectory(at: $0, includingPropertiesForKeys: nil)) ?? []
            }
            for candidate in candidates where candidate.pathExtension == "app" && Bundle(url: candidate)?.bundleIdentifier == identifier {
                paths.insert(candidate.path)
            }
        }
        let target = url.standardizedFileURL.path
        return paths.map { URL(fileURLWithPath: $0).standardizedFileURL }.filter { copy in
            let parents = copy.deletingLastPathComponent().pathComponents
            return copy.path != target && copy.pathExtension == "app" && !parents.contains(".Trash")
                && !parents.contains { ["app", "framework", "bundle", "appex"].contains(($0 as NSString).pathExtension.lowercased()) }
        }
    }

    /// The team identifier and app groups in the code signature at `url`. Reads the signature without
    /// validating it, which is fast and needs no network.
    static func signingInfo(_ url: URL) -> (team: String?, groups: [String]) {
        var code: SecStaticCode?
        guard SecStaticCodeCreateWithPath(url as CFURL, [], &code) == errSecSuccess, let code else { return (nil, []) }
        var information: CFDictionary?
        guard SecCodeCopySigningInformation(code, SecCSFlags(rawValue: kSecCSSigningInformation), &information) == errSecSuccess,
              let dictionary = information as? [String: Any] else { return (nil, []) }
        let entitlements = dictionary[kSecCodeInfoEntitlementsDict as String] as? [String: Any]
        return (dictionary[kSecCodeInfoTeamIdentifier as String] as? String,
                entitlements?["com.apple.security.application-groups"] as? [String] ?? [])
    }

    private static func embeddedBundles(in url: URL) -> [URL] {
        embeddedFolders.flatMap { folder -> [URL] in
            let directory = url.appendingPathComponent(folder.path)
            let entries = (try? FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil)) ?? []
            return entries.filter { folder.extensions.contains($0.pathExtension.lowercased()) }
        }
    }

    /// Privileged helpers (`SMPrivilegedExecutables`), helper tools in `Contents/Library/LaunchServices`,
    /// and launchd jobs the app registers through `SMAppService` (`Contents/Library/LaunchDaemons` and
    /// `LaunchAgents`).
    private static func helperIdentifiers(in url: URL, info: [String: Any]) -> [String] {
        var identifiers = Array((info["SMPrivilegedExecutables"] as? [String: Any] ?? [:]).keys)
        for folder in ["Contents/Library/LaunchServices", "Contents/Library/LaunchDaemons", "Contents/Library/LaunchAgents"] {
            let entries = (try? FileManager.default.contentsOfDirectory(atPath: url.appendingPathComponent(folder).path)) ?? []
            identifiers += entries.map(AppLeftoverRules.stem(of:))
        }
        return identifiers
    }

    /// An uninstaller app in the bundle's Resources, in the folder the app lives in (when that folder is the
    /// vendor's own), or next to it named after the app.
    private static func vendorUninstaller(for url: URL, names: [String]) -> URL? {
        let isUninstaller = { (candidate: URL) in
            candidate.pathExtension == "app" && candidate.lastPathComponent.localizedCaseInsensitiveContains("uninstall")
        }
        let resources = url.appendingPathComponent("Contents/Resources")
        if let inside = (try? FileManager.default.contentsOfDirectory(at: resources, includingPropertiesForKeys: nil))?.first(where: isUninstaller) {
            return inside
        }
        let parent = url.deletingLastPathComponent()
        let shared = ["/Applications", FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Applications").path]
        let siblings = (try? FileManager.default.contentsOfDirectory(at: parent, includingPropertiesForKeys: nil)) ?? []
        return siblings.first { sibling in
            isUninstaller(sibling) && (!shared.contains(parent.standardizedFileURL.path)
                || names.contains { sibling.lastPathComponent.localizedCaseInsensitiveContains($0) })
        }
    }

    private static func attribute(_ item: MDItem?, _ name: String) -> CFTypeRef? {
        guard let item else { return nil }
        return MDItemCopyAttribute(item, name as CFString)
    }
}
