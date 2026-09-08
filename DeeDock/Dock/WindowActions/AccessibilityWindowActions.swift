import AppKit
import ApplicationServices

extension AccessibilityApplicationWindowService {
    /// Retained AX equality plus process birth time avoids title/frame guessing and PID reuse.
    /// Re-enumeration must contain exactly one equal element; no replacement target is selected.
    func validatedHandle(_ token: ApplicationWindowToken) throws -> Handle {
        try Task.checkCancellation()
        guard AXIsProcessTrusted() else { throw WindowActionError.permission }
        guard let handle = handles[token], let birth = handle.launchDate,
              let app = NSRunningApplication(processIdentifier: handle.processIdentifier),
              !app.isTerminated, app.launchDate == birth else { throw WindowActionError.stale }
        let application = AXUIElementCreateApplication(handle.processIdentifier)
        _ = AXUIElementSetMessagingTimeout(application, messagingTimeout)
        guard let live = try copy(application, attribute: kAXWindowsAttribute as CFString) as? [AXUIElement],
              live.filter({ CFEqual($0, handle.element) }).count == 1,
              string(handle.element, attribute: kAXRoleAttribute as CFString) == kAXWindowRole
        else { throw WindowActionError.stale }
        try Task.checkCancellation()
        guard AXIsProcessTrusted() else { throw WindowActionError.permission }
        return handle
    }

    func actionSummary(_ token: ApplicationWindowToken) async throws -> ApplicationWindowSummary {
        let handle = try validatedHandle(token)
        return ApplicationWindowSummary(token: token, processIdentifier: handle.processIdentifier,
            title: string(handle.element, attribute: kAXTitleAttribute as CFString), frame: rect(handle.element),
            isMinimized: boolean(handle.element, attribute: kAXMinimizedAttribute as CFString) ?? false,
            isMain: boolean(handle.element, attribute: kAXMainAttribute as CFString) ?? false)
    }

    func capabilities(_ token: ApplicationWindowToken) async throws -> WindowActionCapabilities {
        try actionCapabilities(token)
    }

    private func actionCapabilities(_ token: ApplicationWindowToken) throws -> WindowActionCapabilities {
        let handle = try validatedHandle(token)
        let window = handle.element
        let children = (try? copy(window, attribute: kAXChildrenAttribute as CFString)) as? [AXUIElement]
        // AXFullScreen is optional app-provided metadata, not a portable SDK constant.
        // Read it only when advertised through the public AX attribute-enumeration API.
        // The fullscreen button alone cannot distinguish entry from exit. Unknown stays unavailable.
        try prepareElement(window)
        var attributeNames: CFArray?
        try check(AXUIElementCopyAttributeNames(window, &attributeNames))
        let exposesFullscreen = (attributeNames as? [String])?.contains("AXFullScreen") == true
        let fullscreen = exposesFullscreen ? boolean(window, attribute: "AXFullScreen" as CFString) : nil
        var restricted = string(window, attribute: kAXSubroleAttribute as CFString) != kAXStandardWindowSubrole
            || fullscreen != false
            || boolean(window, attribute: kAXModalAttribute as CFString) != false
            || children?.contains(where: { string($0, attribute: kAXRoleAttribute as CFString) == kAXSheetRole }) == true
        let application = AXUIElementCreateApplication(handle.processIdentifier)
        _ = AXUIElementSetMessagingTimeout(application, messagingTimeout)
        let appWindows = try copy(application, attribute: kAXWindowsAttribute as CFString) as? [AXUIElement]
        let appModal = appWindows?.contains {
            boolean($0, attribute: kAXModalAttribute as CFString) == true
                || string($0, attribute: kAXRoleAttribute as CFString) == kAXSheetRole
        } != false
        let minimized = boolean(window, attribute: kAXMinimizedAttribute as CFString)
        restricted = restricted || appModal
        let frame = rect(window)
        let canResize = !restricted && minimized == false && isSettable(window, attribute: kAXSizeAttribute as CFString)
        let canUndo = undoFrames[token].map { previous in
            canResize || previous.size == frame?.size
        } ?? false
        return WindowActionCapabilities(
            minimized: minimized ?? false,
            canMinimize: !restricted && minimized != nil && isSettable(window, attribute: kAXMinimizedAttribute as CFString),
            canClose: !restricted && closeButton(window) != nil,
            canMove: !restricted && minimized == false && frame.map(WindowPlacementPolicy.valid) == true && isSettable(window, attribute: kAXPositionAttribute as CFString),
            canResize: canResize,
            canUndo: canUndo,
            frame: frame, restricted: restricted)
    }

    private func closeButton(_ window: AXUIElement) -> AXUIElement? {
        guard let value = try? copy(window, attribute: kAXCloseButtonAttribute as CFString),
              CFGetTypeID(value) == AXUIElementGetTypeID() else { return nil }
        let button = value as! AXUIElement
        guard (try? prepareElement(button)) != nil else { return nil }
        var actions: CFArray?
        guard boolean(button, attribute: kAXEnabledAttribute as CFString) == true,
              AXUIElementCopyActionNames(button, &actions) == .success,
              (actions as? [String])?.contains(kAXPressAction) == true else { return nil }
        return button
    }

    /// Every write has its own revalidation and cancellation gate. A partial geometry write is
    /// reported without rollback or retry: another mutation could overwrite a native app decision.
    func perform(_ action: WindowAction, token: ApplicationWindowToken,
                 displays: [WindowActionDisplay]) async throws -> ApplicationWindowSummary? {
        try validateDisplays(displays)
        let capability = try actionCapabilities(token)
        var handle = try validatedHandle(token)
        switch action {
        case .minimized(let value):
            guard capability.canMinimize else { throw WindowActionError.unsupported }
            try write(token, attribute: kAXMinimizedAttribute as CFString,
                      value: value ? kCFBooleanTrue : kCFBooleanFalse)
            guard boolean(try validatedHandle(token).element, attribute: kAXMinimizedAttribute as CFString) == value
            else { throw WindowActionError.unsupported }
        case .close:
            guard capability.canClose else { throw WindowActionError.unsupported }
            // Deliberate Close may need an unsaved-document dialog. Never restore focus over it.
            let pid = handle.processIdentifier
            let birth = handle.launchDate
            let activated = await MainActor.run {
                guard !Task.isCancelled, AXIsProcessTrusted(),
                      let app = NSRunningApplication(processIdentifier: pid), app.launchDate == birth,
                      !app.isTerminated else { return false }
                return app.activate(options: [])
            }
            guard activated else { throw WindowActionError.stale }
            guard try actionCapabilities(token).canClose else { throw WindowActionError.unsupported }
            handle = try validatedHandle(token)
            guard let button = closeButton(handle.element) else { throw WindowActionError.unsupported }
            try Task.checkCancellation()
            guard AXIsProcessTrusted() else { throw WindowActionError.permission }
            // Consume Close before AXPress, including timeout: never issue it twice for this token.
            handles[token] = nil
            undoFrames[token] = nil
            try performNativeAction(button, action: kAXPressAction as CFString)
            return nil
        case .place(let placement, let displayID):
            guard capability.canMove, let original = capability.frame,
                  WindowPlacementPolicy.valid(original),
                  let destination = displays.first(where: { $0.id == displayID }),
                  let source = WindowPlacementPolicy.current(original, displays: displays),
                  WindowPlacementPolicy.valid(destination.usable),
                  capability.canResize || placement == .move || placement == .center
            else { throw WindowActionError.unsupported }
            let requested = WindowPlacementPolicy.requested(placement, frame: original,
                source: source.usable, destination: destination.usable, resizable: capability.canResize)
            undoFrames[token] = original
            try geometry(token, requested: requested, usable: destination.usable, resize: capability.canResize && requested.size != original.size, displays: displays)
        case .undo:
            guard capability.canMove, capability.canUndo, let original = undoFrames.removeValue(forKey: token),
                  let destination = WindowPlacementPolicy.current(original, displays: displays)
            else { throw WindowActionError.unsupported }
            try geometry(token, requested: original, usable: destination.usable, resize: capability.canResize, displays: displays)
        }
        handle = try validatedHandle(token)
        return ApplicationWindowSummary(token: token, processIdentifier: handle.processIdentifier,
            title: string(handle.element, attribute: kAXTitleAttribute as CFString), frame: rect(handle.element),
            isMinimized: boolean(handle.element, attribute: kAXMinimizedAttribute as CFString) ?? false,
            isMain: boolean(handle.element, attribute: kAXMainAttribute as CFString) ?? false)
    }

    private func geometry(_ token: ApplicationWindowToken, requested: CGRect, usable: CGRect, resize: Bool, displays: [WindowActionDisplay]) throws {
        guard WindowPlacementPolicy.valid(requested), WindowPlacementPolicy.valid(usable) else { throw WindowActionError.unsupported }
        try validateDisplays(displays)
        if resize {
            var size = requested.size
            guard let value = AXValueCreate(.cgSize, &size) else { throw WindowActionError.unsupported }
            try validateDisplays(displays)
            try write(token, attribute: kAXSizeAttribute as CFString, value: value, displays: displays)
        }
        let handle = try validatedHandle(token)
        guard let accepted = rect(handle.element) else { throw WindowActionError.stale }
        var frame = CGRect(origin: requested.origin, size: accepted.size)
        frame = WindowPlacementPolicy.fit(frame, into: usable)
        var point = frame.origin
        guard let value = AXValueCreate(.cgPoint, &point) else { throw WindowActionError.unsupported }
        try validateDisplays(displays)
        try write(token, attribute: kAXPositionAttribute as CFString, value: value, displays: displays)
        guard let actual = rect(try validatedHandle(token).element),
              abs(actual.minX - frame.minX) < 2, abs(actual.minY - frame.minY) < 2,
              abs(actual.width - requested.width) < 2, abs(actual.height - requested.height) < 2
        else { throw WindowActionError.constrained }
    }

    private func validateDisplays(_ displays: [WindowActionDisplay]) throws {
        try Task.checkCancellation()
        guard !displays.isEmpty, displays.allSatisfy({
            CGDisplayIsActive($0.runtimeID) != 0 && CGDisplayBounds($0.runtimeID) == $0.frame
        }) else { throw WindowActionError.stale }
    }

    private func write(_ token: ApplicationWindowToken, attribute: CFString, value: CFTypeRef,
                       displays: [WindowActionDisplay]? = nil) throws {
        let capability = try actionCapabilities(token)
        let permitted = attribute == kAXMinimizedAttribute as CFString ? capability.canMinimize
            : attribute == kAXSizeAttribute as CFString ? capability.canResize : capability.canMove
        guard permitted else { throw WindowActionError.unsupported }
        let handle = try validatedHandle(token)
        guard isSettable(handle.element, attribute: attribute) else { throw WindowActionError.unsupported }
        try Task.checkCancellation()
        guard AXIsProcessTrusted() else { throw WindowActionError.permission }
        if let displays { try validateDisplays(displays) }
        try set(handle.element, attribute: attribute, value: value)
    }
}
