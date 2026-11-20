import Observation
import SwiftUI

/// What the Drop to Place overlay draws. Every frame is in global AppKit coordinates; each
/// display's overlay view converts to its own top-left space.
@MainActor @Observable
final class DropPlacementOverlayModel {
    /// The armed ghost that follows the pointer.
    struct Ghost: Equatable {
        var frame: CGRect
        var title: String
        var subtitle: String
        var tint: Color
    }

    /// The dashed "Last here" or "Now here" outline.
    struct Outline: Equatable {
        var frame: CGRect
        var label: String
        /// Brighter while the magnet holds the target on this frame.
        var hot: Bool
    }

    /// A landing pad left behind after release, until the window arrives.
    struct Pad: Identifiable, Equatable {
        enum Phase: Equatable {
            /// Waiting for the window; the glow breathes.
            case waiting
            /// The window arrived: fade out while growing slightly, handing off to it.
            case handoff
            /// Timeout or failure: fade out quietly.
            case fading
        }
        let id: UUID
        let applicationID: String
        var frame: CGRect
        var title: String
        var tint: Color
        var phase: Phase = .waiting
    }

    var ghost: Ghost?
    var outline: Outline?
    var pads: [Pad] = []
    /// Read from the workspace when a drag starts.
    var reduceMotion = false
    var reduceTransparency = false

    var isEmpty: Bool { ghost == nil && outline == nil && pads.isEmpty }
}
