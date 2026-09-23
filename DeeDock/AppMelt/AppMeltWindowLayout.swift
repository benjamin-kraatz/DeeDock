import AppKit
import ApplicationServices

nonisolated enum AppMeltLayoutFailure: Error { case minimumSize, unequalHeights, positionRefused }

extension AccessibilityApplicationWindowService {
    /// Requests sizes, then lays out the sizes the apps actually accept. Minimum window sizes
    /// enlarge the pair rather than aborting after the first member's partial resize.
    /// The caller must use the returned frames for chrome and subsequent notification matching.
    /// Sleep is capped for the whole call. A missed notification still gets a few reads;
    /// exceeding the budget throws and does not send the mutation again.
    func meltLayout(_ tokens: [ApplicationWindowToken], frames: [CGRect], displays: [WindowActionDisplay],
                    settle: AppMeltSettleWait? = nil) async throws -> [CGRect] {
        guard tokens.count == 2, frames.count == 2,
              let display = WindowPlacementPolicy.current(frames[0].union(frames[1]), displays: displays)
        else { throw WindowActionError.unsupported }
        for token in tokens { try ensureSessionOpen(token.sessionID) }
        try meltValidateDisplay(display)
        for token in tokens {
            let caps = try actionCapabilities(token)
            guard caps.canMove, caps.canResize else { throw WindowActionError.unsupported }
        }
        let deadline = ContinuousClock.now.advanced(by: .milliseconds(1600))
        var accepted: [CGRect] = []
        for (token, frame) in zip(tokens, frames) {
            accepted.append(try await meltResize(token, to: frame.size, display: display, settle: settle, deadline: deadline))
        }
        // Both bottoms must meet the shared rim. Apps can round dimensions or enforce a larger
        // minimum height. Negotiate a common accepted height with a bounded number of writes.
        for _ in 0..<3 {
            let height = max(accepted[0].height, accepted[1].height)
            if abs(accepted[0].height - accepted[1].height) < 2 { break }
            for index in tokens.indices where abs(accepted[index].height - height) >= 2 {
                accepted[index] = try await meltResize(tokens[index], to: CGSize(width: accepted[index].width, height: height),
                    display: display, settle: settle, deadline: deadline)
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
            try ensureSessionOpen(tokens[index].sessionID)
            try meltRequireBudget(deadline)
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
            for attempt in 0..<3 {
                try meltValidateDisplay(display)
                if let actual = rect(try validatedHandle(tokens[index]).element),
                   AppMeltGeometry.nearlyEqual(actual, accepted[index]) {
                    settled = actual
                    break
                }
                guard attempt < 2 else { break }
                try await meltPause(settle, until: deadline, cap: .milliseconds(200))
            }
            guard let settled else { throw AppMeltLayoutFailure.positionRefused }
            accepted[index] = settled
        }
        return accepted
    }

    private func meltResize(_ token: ApplicationWindowToken, to size: CGSize, display: WindowActionDisplay,
                            settle: AppMeltSettleWait?, deadline: ContinuousClock.Instant) async throws -> CGRect {
        try ensureSessionOpen(token.sessionID)
        try meltRequireBudget(deadline)
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
        var latest = initial
        for attempt in 0..<4 {
            if attempt > 0 { try await meltPause(settle, until: deadline, cap: .milliseconds(200)) }
            try meltValidateDisplay(display)
            guard let actual = rect(try validatedHandle(token).element), WindowPlacementPolicy.valid(actual) else {
                throw WindowActionError.stale
            }
            latest = actual
            if actual.size == size { return actual }
            stable = actual.size == previous.size ? stable + 1 : 0
            previous = actual
            if stable >= 2, actual.size != initial.size { return actual }
        }
        if !timedOut { return latest } // An app may clamp at its current size.
        throw ApplicationWindowServiceError.accessibility(AXError.cannotComplete.rawValue)
    }

    private func meltRequireBudget(_ deadline: ContinuousClock.Instant) throws {
        try Task.checkCancellation()
        guard ContinuousClock.now < deadline else {
            throw ApplicationWindowServiceError.accessibility(AXError.cannotComplete.rawValue)
        }
    }

    /// Probes a retained window until `ready`, the read budget, or the time budget runs out.
    /// A settle notification wakes the wait. A missed notification still gets the remaining reads.
    /// Returns false when the budget is exhausted; callers throw their existing failure.
    func meltWaitUntil(budget: Duration, maximumReads: Int, settle: AppMeltSettleWait?,
                       ready: () throws -> Bool) async throws -> Bool {
        let deadline = ContinuousClock.now.advanced(by: budget)
        var probes = 0
        while probes < maximumReads {
            try Task.checkCancellation()
            probes += 1
            if try ready() { return true }
            guard probes < maximumReads else { break }
            let remaining = ContinuousClock.now.duration(to: deadline)
            guard remaining > .zero else { break }
            if let settle {
                let baseline = await settle.generation()
                guard probes < maximumReads else { break }
                probes += 1
                if try ready() { return true }
                guard probes < maximumReads else { break }
                _ = await settle.wait(baseline, min(remaining, .milliseconds(250)))
            } else {
                try await Task.sleep(for: min(remaining, .milliseconds(80)))
            }
        }
        return false
    }

    /// Waits for a settle notification or the remaining budget, whichever comes first.
    /// Does not read AX and does not send another mutation.
    private func meltPause(_ settle: AppMeltSettleWait?, until deadline: ContinuousClock.Instant, cap: Duration) async throws {
        try Task.checkCancellation()
        let remaining = ContinuousClock.now.duration(to: deadline)
        guard remaining > .zero else {
            throw ApplicationWindowServiceError.accessibility(AXError.cannotComplete.rawValue)
        }
        let slice = min(remaining, cap)
        if let settle {
            let baseline = await settle.generation()
            _ = await settle.wait(baseline, slice)
        } else {
            try await Task.sleep(for: min(slice, .milliseconds(50)))
        }
        try Task.checkCancellation()
    }

    private func meltValidateDisplay(_ display: WindowActionDisplay) throws {
        try Task.checkCancellation()
        guard CGDisplayIsActive(display.runtimeID) != 0, CGDisplayBounds(display.runtimeID) == display.frame else {
            throw WindowActionError.stale
        }
    }
}
