import Foundation

/// Why macOS refused to list a folder stack's directory.
nonisolated enum FolderStackAccessDenial: Equatable, Sendable {
    /// macOS privacy protection blocked the read. Full Disk Access lifts it. Time Machine backup
    /// disks are the common case.
    case privacyProtection
    /// The account lacks file permissions, which no privacy setting changes.
    case filePermissions

    /// Nil unless `error` is Foundation's no-permission read error. The underlying POSIX code
    /// tells the two causes apart: privacy protection reports `EPERM`, file permissions `EACCES`.
    init?(_ error: any Error) {
        let error = error as NSError
        guard error.domain == NSCocoaErrorDomain, error.code == NSFileReadNoPermissionError else { return nil }
        let underlying = error.userInfo[NSUnderlyingErrorKey] as? NSError
        let blockedByPrivacy = underlying?.domain == NSPOSIXErrorDomain && underlying?.code == Int(EPERM)
        self = blockedByPrivacy ? .privacyProtection : .filePermissions
    }
}
