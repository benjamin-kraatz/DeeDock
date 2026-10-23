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
/// release until that release has been verified, and on any missing symbol or unexpected result
/// type. Callers treat every failure as "no background applications" and show nothing.
///
/// Every call blocks on Launch Services IPC. Call it off the main actor.
nonisolated enum LaunchServicesBackgroundReader {
    /// Why the reader is off for this session.
    enum Unavailability: String, Error, Sendable {
        /// The SPI is verified for macOS 27 only.
        case unsupportedSystem
        /// A function or key is missing from Launch Services.
        case missingInterface
        /// Launch Services returned something other than an array of application records.
        case unexpectedResult
    }

    /// Lists regular applications that are running in background, merged by bundle.
    ///
    /// Only records of the Foreground application type are included, as in the system Dock;
    /// background-only agents and menu bar apps have no tile there either. An application is
    /// reported only when at least one remaining process belongs to the current user and is
    /// still alive. Such an app can be watched and stopped, so DOKK never shows a background
    /// state it cannot end.
    static func read() -> Result<[BackgroundApplication], Unavailability> {
        let spi: Interface
        switch interface {
        case .success(let resolved): spi = resolved
        case .failure(let reason): return .failure(reason)
        }
        guard let records = spi.copyMatching(defaultSession, spi.includeExitedOptions)?.takeRetainedValue(),
              CFGetTypeID(records) == CFArrayGetTypeID() else { return .failure(.unexpectedResult) }
        var applications: [URL: BackgroundApplication] = [:]
        for record in (records as NSArray) as [AnyObject] {
            guard let application = application(for: record as CFTypeRef, using: spi) else { continue }
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
        return .success(applications.values.sorted { $0.bundleURL.path < $1.bundleURL.path })
    }

    /// `kLSDefaultSessionID`, the current login session.
    private static let defaultSession: Int32 = -2

    /// Resolved once per launch. A failure keeps the reader off until DOKK relaunches.
    private static let interface = Interface.resolve()

    private static func application(for record: CFTypeRef, using spi: Interface) -> BackgroundApplication? {
        // Most records are ordinary running apps, so ask for the two deciding keys first.
        guard let state = spi.information(record, [spi.backgroundKey, spi.typeKey]),
              (state[spi.backgroundKey] as? NSNumber)?.boolValue == true,
              state[spi.typeKey] as? String == spi.foregroundType,
              let details = spi.information(record, [spi.bundlePathKey, spi.displayNameKey,
                                                     kCFBundleIdentifierKey as String,
                                                     spi.coalitionPIDsKey, spi.childApplicationsKey]),
              let path = details[spi.bundlePathKey] as? String, !path.isEmpty else { return nil }

        // Coalition members that are not foreground apps, as counted by the flag itself. A
        // foreground app sharing the coalition has its own tile and must never be stopped here.
        var pids = ((details[spi.coalitionPIDsKey] as? [NSNumber]) ?? []).map(\.int32Value)
        for child in (details[spi.childApplicationsKey] as? [AnyObject]) ?? [] {
            if let pid = spi.information(child as CFTypeRef, [spi.pidKey])?[spi.pidKey] as? NSNumber {
                pids.append(pid.int32Value)
            }
        }
        let processes = Set(pids.compactMap(BackgroundProcess.init(pid:))).sorted { $0.pid < $1.pid }
        guard !processes.isEmpty else { return nil }

        let url = URL(fileURLWithPath: path, isDirectory: true).standardizedFileURL
        let displayName = details[spi.displayNameKey] as? String
        return BackgroundApplication(
            bundleURL: url, bundleIdentifier: details[kCFBundleIdentifierKey as String] as? String,
            name: displayName.flatMap { $0.isEmpty ? nil : $0 } ?? url.deletingPathExtension().lastPathComponent,
            processes: processes)
    }

    /// The private functions and keys, looked up by name in the loaded CoreServices image.
    ///
    /// The values are immutable after `resolve()`, and Launch Services documents its client
    /// calls as thread-safe; `@unchecked` only covers the CF dictionary and C function pointers.
    private struct Interface: @unchecked Sendable {
        typealias CopyMatching = @convention(c) (Int32, CFDictionary?) -> Unmanaged<CFArray>?
        typealias CopyInformation = @convention(c) (Int32, CFTypeRef, CFArray?) -> Unmanaged<CFDictionary>?

        let copyMatching: CopyMatching
        let copyInformation: CopyInformation
        let includeExitedOptions: CFDictionary
        let backgroundKey: String
        let typeKey: String
        let foregroundType: String
        let bundlePathKey: String
        let displayNameKey: String
        let pidKey: String
        let coalitionPIDsKey: String
        let childApplicationsKey: String

        /// Copies `keys` for one record, or `nil` when the record vanished or the reply has
        /// an unexpected type.
        func information(_ record: CFTypeRef, _ keys: [String]) -> [String: Any]? {
            guard let reply = copyInformation(defaultSession, record, keys as CFArray)?.takeRetainedValue(),
                  CFGetTypeID(reply) == CFDictionaryGetTypeID() else { return nil }
            return reply as? [String: Any]
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
                backgroundKey: background, typeKey: type, foregroundType: foreground,
                bundlePathKey: bundlePath, displayNameKey: displayName, pidKey: pid,
                coalitionPIDsKey: coalitionPIDs, childApplicationsKey: children))
        }

        /// Reads an exported `CFStringRef` constant.
        private static func key(_ image: UnsafeMutableRawPointer, _ name: String) -> String? {
            guard let address = dlsym(image, name),
                  let value = UnsafeRawPointer(address).load(as: Unmanaged<CFString>?.self) else { return nil }
            return value.takeUnretainedValue() as String
        }
    }
}
