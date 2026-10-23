import CoreFoundation
import Darwin
import Foundation

/// Reads macOS 27's "Running in Background" state from Launch Services.
///
/// macOS 27 keeps an application's Launch Services record after its main process exits while
/// processes in its resource coalition, or non-foreground child applications, are still alive.
/// The system Dock shows such records with a muted indicator. No public API exposes the state:
/// `NSWorkspace.runningApplications` drops the app when its main process exits.
///
/// The reader uses private Launch Services SPI, and only to read:
/// - `_LSCopyMatchingApplications(session, options)` with the include-exited option returns
///   every application record, including exited ones.
/// - `_LSCopyApplicationInformation(session, asn, keys)` copies the requested keys. The
///   background flag is computed, so it is present only when requested by name.
///
/// Both signatures were verified against `lsappinfo` and the Dock on macOS 27.0.1. `dlsym` can
/// prove that a symbol exists but not that its signature is unchanged, and calling a changed
/// signature could crash DOKK. The reader therefore switches itself off on any other major
/// release until that release has been verified, on any missing symbol, and on any reply whose
/// shape differs from the verified one. Callers treat every failure as "no background
/// applications" and show nothing.
///
/// Every call blocks on Launch Services IPC. Call it off the main actor.
nonisolated enum LaunchServicesBackgroundReader {
    /// Why the reader is off for this session.
    enum Unavailability: String, Error, Sendable {
        /// The SPI is verified for macOS 27 only.
        case unsupportedSystem
        /// A function or key is missing from Launch Services.
        case missingInterface
        /// A reply did not have the verified shape: the list is not an array, a record's reply is
        /// not a dictionary, or a value has another type.
        case unexpectedResult
    }

    /// Lists regular applications that are running in background, merged by bundle.
    static func read() -> Result<[BackgroundApplication], Unavailability> {
        switch interface {
        case .success(let spi): read(from: spi)
        case .failure(let reason): .failure(reason)
        }
    }

    /// Parses every record `source` lists into background applications, merged by bundle.
    ///
    /// Only records of the Foreground application type are included, as in the system Dock;
    /// background-only agents and menu bar apps have no tile there either. An application is
    /// reported only when at least one remaining process belongs to the current user and is
    /// still alive. Such an app can be watched and stopped, so DOKK never shows a background
    /// state it cannot end.
    ///
    /// A record that vanished between the listing and its reply is skipped: its app finished
    /// exiting, which is ordinary. Any reply with another shape fails the whole read with
    /// `unexpectedResult`. It means the private interface changed, and the records that did
    /// parse could be wrong as well, so the feature turns off instead of showing them.
    static func read(from source: some BackgroundRecordSource) -> Result<[BackgroundApplication], Unavailability> {
        guard let records = source.records() else { return .failure(.unexpectedResult) }
        var applications: [URL: BackgroundApplication] = [:]
        do {
            for record in records {
                guard let application = try application(for: record, in: source) else { continue }
                // Quitting a relaunched app while the first instance's helpers still run leaves two
                // records for one bundle. The Dock has one tile for it, and Stop ends both sets.
                if let existing = applications[application.bundleURL] {
                    let processes = Set(existing.processes).union(application.processes)
                    applications[application.bundleURL] = BackgroundApplication(
                        bundleURL: existing.bundleURL, bundleIdentifier: existing.bundleIdentifier,
                        name: existing.name, processes: processes.sorted { $0.pid < $1.pid })
                } else {
                    applications[application.bundleURL] = application
                }
            }
        } catch {
            return .failure(.unexpectedResult)
        }
        return .success(applications.values.sorted { $0.bundleURL.path < $1.bundleURL.path })
    }

    /// `kLSDefaultSessionID`, the current login session.
    private static let defaultSession: Int32 = -2

    /// Resolved once per launch. A failure keeps the reader off until DOKK relaunches.
    private static let interface = Interface.resolve()

    private static func application(for record: AnyObject,
                                    in source: some BackgroundRecordSource) throws(Unavailability) -> BackgroundApplication? {
        let keys = source.keys
        // Most records are ordinary running apps, so ask for the two deciding keys first.
        guard let state = try values(source.information(record, [keys.background, keys.type])),
              try value(state, keys.background, as: NSNumber.self)?.boolValue == true,
              try value(state, keys.type, as: String.self) == keys.foregroundType,
              let details = try values(source.information(record, [keys.bundlePath, keys.displayName,
                                                                   keys.bundleIdentifier, keys.coalitionPIDs,
                                                                   keys.childApplications])),
              let path = try value(details, keys.bundlePath, as: String.self), !path.isEmpty else { return nil }
        // Every value is type-checked before liveness decides anything, so a malformed reply
        // fails the read even for a record whose processes have all exited.
        let displayName = try value(details, keys.displayName, as: String.self)
        let bundleIdentifier = try value(details, keys.bundleIdentifier, as: String.self)

        // Coalition members that are not foreground apps, as counted by the flag itself. A
        // foreground app sharing the coalition has its own tile and must never be stopped here.
        var pids = try (value(details, keys.coalitionPIDs, as: [NSNumber].self) ?? []).map(\.int32Value)
        for child in try value(details, keys.childApplications, as: [AnyObject].self) ?? [] {
            if let reply = try values(source.information(child, [keys.pid])),
               let pid = try value(reply, keys.pid, as: NSNumber.self) {
                pids.append(pid.int32Value)
            }
        }
        let processes = Set(pids.compactMap(BackgroundProcess.init(pid:))).sorted { $0.pid < $1.pid }
        guard !processes.isEmpty else { return nil }

        let url = URL(fileURLWithPath: path, isDirectory: true).standardizedFileURL
        return BackgroundApplication(
            bundleURL: url, bundleIdentifier: bundleIdentifier,
            name: displayName.flatMap { $0.isEmpty ? nil : $0 } ?? url.deletingPathExtension().lastPathComponent,
            processes: processes)
    }

    /// A reply's values, or `nil` for a record that vanished. Throws for a malformed reply.
    private static func values(_ reply: BackgroundRecordReply) throws(Unavailability) -> [String: Any]? {
        switch reply {
        case .vanished: nil
        case .malformed: throw .unexpectedResult
        case .values(let values): values
        }
    }

    /// The value for `key`, or `nil` when the reply leaves it out. Throws when the value has
    /// another type, which an absent key never causes.
    private static func value<T>(_ values: [String: Any], _ key: String, as type: T.Type) throws(Unavailability) -> T? {
        guard let raw = values[key], !(raw is NSNull) else { return nil }
        guard let typed = raw as? T else { throw .unexpectedResult }
        return typed
    }

    /// The private functions and keys, looked up by name in the loaded CoreServices image.
    ///
    /// The values are immutable after `resolve()`, and Launch Services documents its client
    /// calls as thread-safe; `@unchecked` only covers the CF dictionary and C function pointers.
    private struct Interface: BackgroundRecordSource, @unchecked Sendable {
        typealias CopyMatching = @convention(c) (Int32, CFDictionary?) -> Unmanaged<CFArray>?
        typealias CopyInformation = @convention(c) (Int32, CFTypeRef, CFArray?) -> Unmanaged<CFDictionary>?

        let copyMatching: CopyMatching
        let copyInformation: CopyInformation
        let includeExitedOptions: CFDictionary
        let keys: BackgroundRecordKeys

        func records() -> [AnyObject]? {
            guard let records = copyMatching(defaultSession, includeExitedOptions)?.takeRetainedValue(),
                  CFGetTypeID(records) == CFArrayGetTypeID() else { return nil }
            return (records as NSArray) as [AnyObject]
        }

        /// Launch Services answers `NULL` for a record whose app has finished exiting.
        func information(_ record: AnyObject, _ keys: [String]) -> BackgroundRecordReply {
            guard let reply = copyInformation(defaultSession, record as CFTypeRef, keys as CFArray)?.takeRetainedValue()
            else { return .vanished }
            guard CFGetTypeID(reply) == CFDictionaryGetTypeID(), let values = reply as? [String: Any] else { return .malformed }
            return .values(values)
        }

        static func resolve() -> Result<Interface, Unavailability> {
            guard ProcessInfo.processInfo.operatingSystemVersion.majorVersion == 27 else {
                return .failure(.unsupportedSystem)
            }
            // AppKit has already loaded CoreServices; this returns the existing image. The
            // handle is intentionally never closed.
            guard let image = dlopen("/System/Library/Frameworks/CoreServices.framework/CoreServices", RTLD_LAZY),
                  let copyMatching = dlsym(image, "_LSCopyMatchingApplications"),
                  let copyInformation = dlsym(image, "_LSCopyApplicationInformation"),
                  let includeExited = key(image, "_kLSApplicationCopyMatchingApplicationsIncludeExitedApplicationsKey"),
                  let background = key(image,
                      "_kLSApplicationExitedButHasRemainingCoalitionPIDsOrNonForegroundChildrenApplicationsKey"),
                  let type = key(image, "_kLSApplicationTypeKey"),
                  let foreground = key(image, "_kLSApplicationForegroundTypeKey"),
                  let bundlePath = key(image, "_kLSBundlePathKey"),
                  let displayName = key(image, "_kLSDisplayNameKey"),
                  let pid = key(image, "_kLSPIDKey"),
                  let coalitionPIDs = key(image, "_kLSApplicationCoalitionNonForegroundApplicationPIDsKey"),
                  let children = key(image, "_kLSApplicationNonForegroundChildApplicationASNsArrayKey")
            else { return .failure(.missingInterface) }
            return .success(Interface(
                copyMatching: unsafeBitCast(copyMatching, to: CopyMatching.self),
                copyInformation: unsafeBitCast(copyInformation, to: CopyInformation.self),
                includeExitedOptions: [includeExited: true] as CFDictionary,
                keys: BackgroundRecordKeys(
                    background: background, type: type, foregroundType: foreground, bundlePath: bundlePath,
                    displayName: displayName, bundleIdentifier: kCFBundleIdentifierKey as String, pid: pid,
                    coalitionPIDs: coalitionPIDs, childApplications: children)))
        }

        /// Reads an exported `CFStringRef` constant.
        private static func key(_ image: UnsafeMutableRawPointer, _ name: String) -> String? {
            guard let address = dlsym(image, name),
                  let value = UnsafeRawPointer(address).load(as: Unmanaged<CFString>?.self) else { return nil }
            return value.takeUnretainedValue() as String
        }
    }
}

/// Launch Services' application records, as `LaunchServicesBackgroundReader` parses them.
///
/// The reader's private interface is the production source. Tests supply replies directly,
/// including malformed ones, without calling Launch Services.
nonisolated protocol BackgroundRecordSource {
    /// The names of the keys to request, and the value that marks a regular app.
    var keys: BackgroundRecordKeys { get }
    /// Every application record, exited ones included, or `nil` when the reply is not a list.
    func records() -> [AnyObject]?
    /// The requested keys of one record.
    func information(_ record: AnyObject, _ keys: [String]) -> BackgroundRecordReply
}

/// One record's reply to a request for keys.
nonisolated enum BackgroundRecordReply {
    /// Launch Services no longer has the record, because its app finished exiting.
    case vanished
    /// The reply is not a dictionary.
    case malformed
    case values([String: Any])
}

/// The key names a record source answers to. Production resolves them from CoreServices.
nonisolated struct BackgroundRecordKeys: Sendable {
    let background: String
    let type: String
    /// The `type` value of a regular, Dock-visible app.
    let foregroundType: String
    let bundlePath: String
    let displayName: String
    let bundleIdentifier: String
    let pid: String
    let coalitionPIDs: String
    let childApplications: String
}
