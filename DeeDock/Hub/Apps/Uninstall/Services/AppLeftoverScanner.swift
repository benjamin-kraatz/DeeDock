import Foundation

/// Finds and measures what an app left on disk. Synchronous and file-system bound; call it off the main
/// actor. It checks `Task.isCancelled` between folders and while measuring.
///
/// Reading another app's container needs Full Disk Access. Without it macOS denies the read silently,
/// with no prompt (verified on macOS 27). Such items are still listed, marked
/// ``AppLeftover/isProtected``, so the sheet can say why they stay.
nonisolated enum AppLeftoverScanner {
    /// Every folder the scanner looks in, in the order the sheet lists them.
    static func roots(home: URL) -> [AppLeftoverRoot] {
        let library = home.appendingPathComponent("Library")
        func user(_ path: String, _ kind: AppLeftover.Kind, _ naming: AppLeftoverRoot.Naming,
                  names: Bool = false) -> AppLeftoverRoot {
            AppLeftoverRoot(url: library.appendingPathComponent(path), kind: kind, domain: .user, naming: naming,
                            allowsNameMatches: names)
        }
        func system(_ path: String, _ kind: AppLeftover.Kind, _ naming: AppLeftoverRoot.Naming) -> AppLeftoverRoot {
            AppLeftoverRoot(url: URL(fileURLWithPath: path), kind: kind, domain: .allUsers, naming: naming,
                            allowsNameMatches: false)
        }
        return [
            user("Containers", .container, .bundle), user("Group Containers", .groupContainer, .group),
            user("Application Scripts", .scripts, .bundleOrGroup),
            user("Application Support", .applicationSupport, .bundle, names: true),
            user("Caches", .caches, .bundle, names: true), user("Preferences", .preferences, .bundle),
            user("Preferences/ByHost", .preferences, .bundle), user("Saved Application State", .savedState, .bundle),
            user("HTTPStorages", .webData, .bundle), user("WebKit", .webData, .bundle), user("Cookies", .webData, .bundle),
            user("Logs", .logs, .bundle, names: true), user("LaunchAgents", .launchAgent, .launchd),
            AppLeftoverRoot(url: home, kind: .homeFolder, domain: .user, naming: .bundle, allowsNameMatches: true),
            system("/Library/Application Support", .applicationSupport, .bundle),
            system("/Library/Caches", .caches, .bundle), system("/Library/Preferences", .preferences, .bundle),
            system("/Library/LaunchAgents", .launchAgent, .launchd),
            system("/Library/LaunchDaemons", .backgroundHelper, .launchd),
            system("/Library/PrivilegedHelperTools", .backgroundHelper, .helper),
        ]
    }

    /// The leftovers of `target`.
    ///
    /// Every result passes ``AppUninstallPathPolicy/allowsData(_:home:)``, and nothing inside the app's
    /// own bundle is returned.
    /// - Parameters:
    ///   - target: The app being uninstalled. Without a bundle identifier only name matches are possible.
    ///   - others: The other installed apps.
    ///   - home: The user's home folder.
    static func scan(_ target: AppUninstallTarget, others: [AppLeftoverRules.OtherApp], home: URL) -> [AppLeftover] {
        let rules = AppLeftoverRules(identity: .init(
            identifiers: [target.bundleIdentifier].compactMap { $0 } + target.embeddedIdentifiers,
            helperIdentifiers: target.helperIdentifiers, appGroups: target.appGroups, names: target.names),
                                     others: others)
        let bundlePath = target.url.standardizedFileURL.path + "/"
        var found: [AppLeftover] = []
        var seen = Set<String>()
        for root in roots(home: home) {
            if Task.isCancelled { return [] }
            let entries = (try? FileManager.default.contentsOfDirectory(atPath: root.url.path))
                ?? exactEntries(in: root, rules: rules)
            for var item in rules.leftovers(in: root, entries: entries) {
                guard seen.insert(item.id).inserted, !item.url.path.hasPrefix(bundlePath),
                      AppUninstallPathPolicy.allowsData(item.url, home: home) else { continue }
                item.isProtected = isProtected(item.url)
                found.append(item)
            }
        }
        return found
    }

    /// The space `url` takes on disk, or ``AppLeftoverMeasure/unreadable`` when only root can read it.
    ///
    /// Allocated rather than logical sizes: a virtual machine's sparse disk image can claim hundreds of
    /// gigabytes while using a few hundred megabytes, and the sheet promises what moving it frees.
    static func measure(_ url: URL) -> AppLeftoverMeasure {
        var isDirectory: ObjCBool = false
        guard FileManager.default.fileExists(atPath: url.path, isDirectory: &isDirectory) else { return .size(0) }
        let keys: [URLResourceKey] = [.totalFileAllocatedSizeKey, .fileAllocatedSizeKey, .isSymbolicLinkKey]
        guard isDirectory.boolValue else { return .size(fileSize(url, keys: keys)) }
        var total: Int64 = 0
        var denied = false
        let enumerator = FileManager.default.enumerator(at: url, includingPropertiesForKeys: keys, options: []) { _, _ in
            denied = true
            return true
        }
        while let item = enumerator?.nextObject() as? URL {
            if Task.isCancelled { break }
            total += fileSize(item, keys: keys)
        }
        return denied && total == 0 ? .unreadable : .size(total)
    }

    /// Whether macOS privacy protection hides `url` from DOKK.
    ///
    /// A container lists its top level even without Full Disk Access; the protected part is its `Data`
    /// folder, so that is what this reads. A group container refuses the top level itself.
    static func isProtected(_ url: URL) -> Bool {
        var isDirectory: ObjCBool = false
        guard FileManager.default.fileExists(atPath: url.path, isDirectory: &isDirectory), isDirectory.boolValue else {
            return false
        }
        do {
            let children = try FileManager.default.contentsOfDirectory(atPath: url.path)
            if children.contains("Data") {
                _ = try FileManager.default.contentsOfDirectory(atPath: url.appendingPathComponent("Data").path)
            }
            return false
        } catch {
            return isPrivacyDenial(error)
        }
    }

    /// True for "Operation not permitted" (`EPERM`) anywhere in the error chain: macOS privacy protection,
    /// as opposed to plain file permissions (`EACCES`).
    static func isPrivacyDenial(_ error: Error) -> Bool {
        var current: NSError? = error as NSError
        while let error = current {
            if error.domain == NSPOSIXErrorDomain, error.code == Int(EPERM) { return true }
            current = error.userInfo[NSUnderlyingErrorKey] as? NSError
        }
        return false
    }

    /// Names to check one by one when a folder can't be listed: the identifiers and groups themselves,
    /// with the extensions per-app files use.
    private static func exactEntries(in root: AppLeftoverRoot, rules: AppLeftoverRules) -> [String] {
        let stems = rules.identity.identifiers + rules.identity.helperIdentifiers + rules.identity.appGroups
        let names = stems.flatMap { stem in [stem] + AppLeftoverRules.strippedExtensions.map { stem + $0 } }
        return names.filter { FileManager.default.fileExists(atPath: root.url.appendingPathComponent($0).path) }
    }

    private static func fileSize(_ url: URL, keys: [URLResourceKey]) -> Int64 {
        guard let values = try? url.resourceValues(forKeys: Set(keys)), values.isSymbolicLink != true else { return 0 }
        return Int64(values.totalFileAllocatedSize ?? values.fileAllocatedSize ?? 0)
    }
}
