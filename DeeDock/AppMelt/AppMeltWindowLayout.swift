import AppKit
import ApplicationServices

nonisolated enum AppMeltLayoutFailure: Error { case minimumSize, unequalHeights, positionRefused }

extension AccessibilityApplicationWindowService {
    /// Requests sizes, then lays out the sizes the apps actually accept. Minimum window sizes
    /// enlarge the pair rather than aborting after the first member's partial resize.
    /// The caller must use the returned frames for chrome and subsequent notification matching.
    func meltLayout(_ tokens: [ApplicationWindowToken], frames: [CGRect], displays: [WindowActionDisplay]) async throws -> [CGRect] {
        guard tokens.count == 2, frames.count == 2,
              let display = WindowPlacementPolicy.current(frames[0].union(frames[1]), displays: displays)
        else { throw WindowActionError.unsupported }
        try meltValidateDisplay(display)
        for token in tokens {
            let caps = try actionCapabilities(token)
            guard caps.canMove, caps.canResize else { throw WindowActionError.unsupported }
        }
        var accepted: [CGRect] = []
        for (token, frame) in zip(tokens, frames) {
            accepted.append(try await meltResize(token, to: frame.size, display: display))
        }
        // Both bottoms must meet the shared rim. Apps can round dimensions or enforce a larger
        // minimum height. Negotiate a common accepted height with a bounded number of writes.
        for _ in 0..<3 {
            let height = max(accepted[0].height, accepted[1].height)
            if abs(accepted[0].height - accepted[1].height) < 2 { break }
            for index in tokens.indices where abs(accepted[index].height - height) >= 2 {
                accepted[index] = try await meltResize(tokens[index], to: CGSize(width: accepted[index].width, height: height), display: display)
            }
        }
        guard abs(accepted[0].height - accepted[1].height) < 2 else { throw AppMeltLayoutFailure.unequalHeights }
        let width = accepted[0].width + accepted[1].width + AppMeltGeometry.divider + AppMeltGeometry.rim * 2
        let height = max(accepted[0].height, accepted[1].height) + AppMeltGeometry.header + AppMeltGeometry.rim
        guard width <= display.usable.width + 1, height <= display.usable.height + 1 else {
            throw AppMeltLayoutFailure.minimumSize
        }
        let outer = WindowPlacementPolicy.fit(CGRect(x: frames[0].minX - AppMeltGeometry.rim,
            y: frames[0].minY - AppMeltGeometry.header, width: width, height: height), into: display.usable)
        accepted[0].origin = CGPoint(x: outer.minX + AppMeltGeometry.rim, y: outer.minY + AppMeltGeometry.header)
        accepted[1].origin = CGPoint(x: accepted[0].maxX + AppMeltGeometry.divider, y: accepted[0].minY)
        for index in tokens.indices {
            let caps = try actionCapabilities(tokens[index])
            guard caps.canMove else { throw WindowActionError.unsupported }
            try meltValidateDisplay(display)
            var point = accepted[index].origin
            guard let value = AXValueCreate(.cgPoint, &point) else { throw WindowActionError.unsupported }
            do {
                try set(try validatedHandle(tokens[index]).element, attribute: kAXPositionAttribute as CFString, value: value)
            } catch ApplicationWindowServiceError.accessibility(let code) where code == AXError.cannotComplete.rawValue {
                // A timed-out mutation can still finish. Verify without sending it again.
            }
            var settled: CGRect?
            for attempt in 0..<16 {
                try meltValidateDisplay(display)
                if let actual = rect(try validatedHandle(tokens[index]).element),
                   AppMeltGeometry.nearlyEqual(actual, accepted[index]) {
                    settled = actual
                    break
                }
                if attempt < 15 { try await Task.sleep(for: .milliseconds(50)) }
            }
            guard let settled else { throw AppMeltLayoutFailure.positionRefused }
            accepted[index] = settled
        }
        return accepted
    }

    private func meltResize(_ token: ApplicationWindowToken, to size: CGSize, display: WindowActionDisplay) async throws -> CGRect {
        guard size.width.isFinite, size.height.isFinite, size.width > 0, size.height > 0,
              try actionCapabilities(token).canResize else { throw WindowActionError.unsupported }
        try meltValidateDisplay(display)
        let handle = try validatedHandle(token)
        guard let initial = rect(handle.element) else { throw WindowActionError.stale }
        if initial.size == size { return initial }
        var requested = size
        guard let value = AXValueCreate(.cgSize, &requested) else { throw WindowActionError.unsupported }
        var timedOut = false
        do {
            try set(handle.element, attribute: kAXSizeAttribute as CFString, value: value)
        } catch ApplicationWindowServiceError.accessibility(let code) where code == AXError.cannotComplete.rawValue {
            timedOut = true
        }
        // AX writes can return before an app publishes its final bounds. Wait for stable
        // accepted dimensions before negotiating the partner's height or placing either app.
        var previous = initial
        var stable = 0
        for attempt in 0..<16 {
            try await Task.sleep(for: .milliseconds(50))
            try meltValidateDisplay(display)
            guard let actual = rect(try validatedHandle(token).element), WindowPlacementPolicy.valid(actual) else {
                throw WindowActionError.stale
            }
            stable = actual.size == previous.size ? stable + 1 : 0
            previous = actual
            if stable >= 3, actual.size != initial.size || actual.size == size { return actual }
            if attempt == 15, !timedOut { return actual } // An app may clamp at its current size.
        }
        throw ApplicationWindowServiceError.accessibility(AXError.cannotComplete.rawValue)
    }

    private func meltValidateDisplay(_ display: WindowActionDisplay) throws {
        try Task.checkCancellation()
        guard CGDisplayIsActive(display.runtimeID) != 0, CGDisplayBounds(display.runtimeID) == display.frame else {
            throw WindowActionError.stale
        }
    }
}
