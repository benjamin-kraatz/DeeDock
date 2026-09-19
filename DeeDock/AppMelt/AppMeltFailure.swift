import Foundation

/// Permission advice is reserved for an actual permission failure. Size and lifecycle failures
/// must stay distinguishable so granting access again is never the generic recovery action.
enum AppMeltFailure {
    static func message(for error: Error) -> LocalizedStringResource {
        switch error {
        case AppMeltLayoutFailure.unequalHeights: .meltHeightMismatch
        case AppMeltLayoutFailure.positionRefused: .meltPositionRefused
        case AppMeltLayoutFailure.minimumSize: .meltSizeConstraint
        case WindowActionError.unsupported: .meltControlUnavailable
        case WindowActionError.stale, ApplicationWindowServiceError.windowUnavailable: .meltWindowGone
        case WindowActionError.permission, ApplicationWindowServiceError.permissionRequired: .meltPermissionRequired
        case ApplicationWindowServiceError.sandboxRestricted: .meltSandboxRestricted
        default: .meltControlFailed
        }
    }
}
