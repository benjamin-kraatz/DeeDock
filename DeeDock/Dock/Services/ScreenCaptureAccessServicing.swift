import AppKit
import CoreGraphics

/// Read-only authorization checks stay separate from the explicit system prompt.
@MainActor
protocol ScreenCaptureAccessServicing: AnyObject {
    var status: ScreenCaptureAccessStatus { get }
    func requestAccess()
    func openSystemSettings()
}

nonisolated enum ScreenCaptureAccessStatus: Equatable, Sendable {
    case enabled
    case notEnabled
    case unavailable
}

/// Public screen-capture authorization APIs plus the matching Privacy pane.
@MainActor
final class SystemScreenCaptureAccessService: ScreenCaptureAccessServicing {
    var status: ScreenCaptureAccessStatus {
        CGPreflightScreenCaptureAccess() ? .enabled : .notEnabled
    }

    func requestAccess() {
        _ = CGRequestScreenCaptureAccess()
    }

    func openSystemSettings() {
        let workspace = NSWorkspace.shared
        let pane = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_ScreenCapture")
        if let pane, workspace.open(pane) { return }
        if let settings = workspace.urlForApplication(withBundleIdentifier: "com.apple.systempreferences") {
            workspace.open(settings)
        }
    }
}
