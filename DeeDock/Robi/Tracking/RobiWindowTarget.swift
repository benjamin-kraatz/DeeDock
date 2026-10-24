import CoreGraphics
import Foundation

/// The window Robi sits on: the frontmost app's focused standard window.
///
/// `frame` is in global top-left points, the space AX and the window server use. Convert with
/// `RobiScreenSpace` before placing AppKit windows.
nonisolated struct RobiWindowTarget: Equatable, Sendable {
    let processIdentifier: pid_t
    let windowID: CGWindowID
    var frame: CGRect
    let applicationName: String
    let bundleIdentifier: String?
    let isFullScreen: Bool
}
