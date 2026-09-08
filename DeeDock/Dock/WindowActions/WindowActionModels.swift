import Foundation
import CoreGraphics

/// Commands address a session token, never an application or a captured window number.
nonisolated enum WindowAction: Equatable, Sendable {
    case minimized(Bool)
    case close
    case place(WindowPlacement, displayID: String)
    case undo
}

nonisolated enum WindowPlacement: CaseIterable, Sendable {
    case move, left, right, center, fill
}

/// All rectangles use global AX/Quartz points, with a downward y axis.
nonisolated struct WindowActionDisplay: Sendable, Equatable {
    let id: String
    let runtimeID: UInt32
    let name: String
    let frame: CGRect
    let usable: CGRect
}

nonisolated struct WindowActionCapabilities: Sendable {
    let minimized: Bool
    let canMinimize: Bool
    let canClose: Bool
    let canMove: Bool
    let canResize: Bool
    let canUndo: Bool
    let frame: CGRect?
    let restricted: Bool
}

nonisolated enum WindowActionError: Error {
    case unsupported, stale, permission, constrained
}

/// Geometry is independent of native writes. Spanning windows use largest full-frame overlap,
/// with input order breaking ties. Oversized windows retain their title bar in the usable area.
nonisolated enum WindowPlacementPolicy {
    static func current(_ frame: CGRect, displays: [WindowActionDisplay]) -> WindowActionDisplay? {
        displays.enumerated().max {
            let a = overlap(frame, $0.element.frame), b = overlap(frame, $1.element.frame)
            return a == b ? $0.offset > $1.offset : a < b
        }?.element
    }

    private static func overlap(_ a: CGRect, _ b: CGRect) -> CGFloat {
        let intersection = a.intersection(b)
        return intersection.isNull ? 0 : intersection.width * intersection.height
    }

    static func valid(_ frame: CGRect) -> Bool {
        [frame.minX, frame.minY, frame.width, frame.height].allSatisfy(\.isFinite)
            && frame.width > 0 && frame.height > 0
    }

    static func fit(_ frame: CGRect, into usable: CGRect) -> CGRect {
        CGRect(x: max(usable.minX, min(frame.minX, usable.maxX - frame.width)),
               y: max(usable.minY, min(frame.minY, usable.maxY - frame.height)),
               width: frame.width, height: frame.height)
    }

    static func requested(_ placement: WindowPlacement, frame: CGRect,
                          source: CGRect, destination: CGRect, resizable: Bool) -> CGRect {
        var result = frame
        switch placement {
        case .move:
            result.origin.x = destination.minX + (frame.minX - source.minX) / max(1, source.width) * destination.width
            result.origin.y = destination.minY + (frame.minY - source.minY) / max(1, source.height) * destination.height
            if resizable {
                result.size.width = min(frame.width, destination.width)
                result.size.height = min(frame.height, destination.height)
            }
        case .left, .right:
            result = CGRect(x: destination.minX + (placement == .right ? destination.width / 2 : 0),
                            y: destination.minY, width: destination.width / 2, height: destination.height)
        case .fill: result = destination
        case .center:
            result.origin = CGPoint(x: destination.midX - frame.width / 2, y: destination.midY - frame.height / 2)
        }
        return fit(result, into: destination)
    }
}
