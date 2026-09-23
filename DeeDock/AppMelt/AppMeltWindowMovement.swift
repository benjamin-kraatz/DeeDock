import AppKit
import ApplicationServices

extension AccessibilityApplicationWindowService {
    /// Translation-only drag path: preflight once per gesture, then write only two positions.
    /// No window-list scans, resize negotiation, or synchronous geometry readback per sample.
    /// The controller coalesces pending positions and reconciles actual geometry on release.
    func meltMove(_ tokens: [ApplicationWindowToken], sessionID: UUID, frames: [CGRect]) throws -> [CGRect] {
        guard tokens.count == 2, frames.count == 2 else { throw WindowActionError.unsupported }
        for token in tokens { try ensureSessionOpen(token.sessionID) }
        try ensureSessionOpen(sessionID)
        if meltMoveHandles[sessionID] == nil {
            for token in tokens {
                guard try actionCapabilities(token).canMove else { throw WindowActionError.unsupported }
            }
            meltMoveHandles[sessionID] = try tokens.map { try validatedHandle($0) }
        }
        guard let members = meltMoveHandles[sessionID] else { throw WindowActionError.stale }
        for (handle, frame) in zip(members, frames) {
            try Task.checkCancellation()
            try ensureSessionOpen(sessionID)
            guard AXIsProcessTrusted() else { throw WindowActionError.permission }
            guard let app = NSRunningApplication(processIdentifier: handle.processIdentifier),
                  !app.isTerminated, app.windowControlLaunchDate == handle.launchDate,
                  WindowPlacementPolicy.valid(frame) else { throw WindowActionError.stale }
            var point = frame.origin
            guard let value = AXValueCreate(.cgPoint, &point) else { throw WindowActionError.unsupported }
            // This exact retained object was preflighted above. A slow source must not queue
            // seconds of old pointer positions. A timeout is ambiguous: reconcile on release
            // rather than retrying an obsolete position or suspending a still-moving window.
            try check(AXUIElementSetMessagingTimeout(handle.element, 0.05))
            defer { _ = AXUIElementSetMessagingTimeout(handle.element, messagingTimeout) }
            let result = AXUIElementSetAttributeValue(handle.element, kAXPositionAttribute as CFString, value)
            if result != .cannotComplete { try check(result) }
        }
        return frames
    }

    func meltEndMove(_ sessionID: UUID) { meltMoveHandles[sessionID] = nil }
}
