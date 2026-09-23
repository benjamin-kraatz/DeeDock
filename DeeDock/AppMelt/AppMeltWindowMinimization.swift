import ApplicationServices

extension AccessibilityApplicationWindowService {
    func meltSummary(_ token: ApplicationWindowToken) throws -> ApplicationWindowSummary {
        let handle = try validatedHandle(token, allowRetainedWindow: true)
        guard let minimized = try meltBoolean(handle.element, attribute: kAXMinimizedAttribute as CFString) else {
            throw WindowActionError.unsupported
        }
        return ApplicationWindowSummary(token: token, processIdentifier: handle.processIdentifier,
            title: string(handle.element, attribute: kAXTitleAttribute as CFString), frame: rect(handle.element),
            isMinimized: minimized,
            isMain: boolean(handle.element, attribute: kAXMainAttribute as CFString) ?? false)
    }

    /// Writes once, then waits for the native minimize animation to settle. App Store reports
    /// AXDialog while minimized, so restoration of an exact retained minimized handle must not
    /// depend on the normal-window geometry policy. Geometry stays gated after restoration.
    /// Readback is notification-driven and capped: a slow app fails into Restore/Unpair
    /// instead of holding the pair busy through a long poll. The write is never repeated.
    func meltSetMinimized(_ minimized: Bool, token: ApplicationWindowToken, settle: AppMeltSettleWait? = nil) async throws {
        try ensureSessionOpen(token.sessionID)
        let handle = try validatedHandle(token, allowRetainedWindow: true)
        guard let current = try meltBoolean(handle.element, attribute: kAXMinimizedAttribute as CFString) else {
            throw WindowActionError.unsupported
        }
        if current != minimized {
            if minimized {
                guard try actionCapabilities(token).canMinimize else { throw WindowActionError.unsupported }
            } else {
                guard try meltBoolean(handle.element, attribute: kAXModalAttribute as CFString) != true,
                      try meltBoolean(handle.element, attribute: "AXFullScreen" as CFString) != true,
                      isSettable(handle.element, attribute: kAXMinimizedAttribute as CFString) else {
                    throw WindowActionError.unsupported
                }
            }
            try ensureSessionOpen(token.sessionID)
            do {
                try set(handle.element, attribute: kAXMinimizedAttribute as CFString,
                        value: minimized ? kCFBooleanTrue : kCFBooleanFalse)
            } catch ApplicationWindowServiceError.accessibility(let code) where code == AXError.cannotComplete.rawValue {
                // A timeout does not establish that the write failed. Read back the exact handle;
                // never send a second mutation while an app may still be animating the first one.
            }
        }
        let ready = try await meltWaitUntil(budget: .milliseconds(800), maximumReads: 3, settle: settle) {
            try self.ensureSessionOpen(token.sessionID)
            let window = try self.validatedHandle(token, allowRetainedWindow: true).element
            guard try self.meltBoolean(window, attribute: kAXMinimizedAttribute as CFString) == minimized else { return false }
            // Restoring may update AXMinimized before the app restores its normal subrole.
            if minimized { return true }
            return try self.meltRestoredWindowCanMove(window)
        }
        guard ready else { throw WindowActionError.unsupported }
    }

    /// Restore polling stays on the retained window. Re-enumerating every application window on
    /// each sample is expensive and can stall the actor behind an unrelated unresponsive window.
    private func meltRestoredWindowCanMove(_ window: AXUIElement) throws -> Bool {
        guard string(window, attribute: kAXSubroleAttribute as CFString) == kAXStandardWindowSubrole,
              try meltBoolean(window, attribute: kAXModalAttribute as CFString) == false,
              let frame = rect(window), WindowPlacementPolicy.valid(frame) else { return false }
        return isSettable(window, attribute: kAXPositionAttribute as CFString)
    }

    /// Unlike the convenience reader used for optional metadata, state-machine reads must retain
    /// AX errors. Treating a timeout as `false` can invert the pair's minimized state.
    private func meltBoolean(_ element: AXUIElement, attribute: CFString) throws -> Bool? {
        guard let value = try copy(element, attribute: attribute) else { return nil }
        guard CFGetTypeID(value) == CFBooleanGetTypeID() else { return nil }
        return CFBooleanGetValue(value as! CFBoolean)
    }
}
