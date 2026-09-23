import AppKit
import ApplicationServices

extension AccessibilityApplicationWindowService {
    /// Rejects reuse of a live source even when discovery produced a different session token.
    func meltOverlaps(_ tokens: [ApplicationWindowToken], existing: [ApplicationWindowToken]) throws -> Bool {
        let proposed = try tokens.map { try validatedHandle($0).element }
        guard proposed.count == 2, !CFEqual(proposed[0], proposed[1]) else { throw WindowActionError.unsupported }
        return existing.contains { token in
            guard let handle = try? validatedHandle(token) else { return false }
            return proposed.contains { CFEqual($0, handle.element) }
        }
    }

    /// Exact focused-window matching prevents chrome covering another document from the same app.
    func meltContainsFocusedWindow(_ tokens: [ApplicationWindowToken]) async throws -> Bool {
        let front = await MainActor.run { NSWorkspace.shared.frontmostApplication?.processIdentifier }
        for token in tokens {
            let handle = try validatedHandle(token)
            guard handle.processIdentifier == front else { continue }
            let app = AXUIElementCreateApplication(handle.processIdentifier)
            try prepareElement(app)
            if let focused = try copy(app, attribute: kAXFocusedWindowAttribute as CFString),
               CFEqual(focused, handle.element) { return true }
        }
        return false
    }

    /// Raising preserves the token and changes no app-wide hidden state or unrelated windows.
    func meltRaise(_ tokens: [ApplicationWindowToken]) async throws {
        for token in tokens { try ensureSessionOpen(token.sessionID) }
        let front = await MainActor.run { NSWorkspace.shared.frontmostApplication?.processIdentifier }
        // PID ordering cannot distinguish two windows of one app. Capture the exact focused
        // member before raising anything and raise it last to preserve the user's selection.
        let members = try tokens.map { try validatedHandle($0) }
        var focused: CFTypeRef?
        if let front {
            let app = AXUIElementCreateApplication(front)
            try prepareElement(app)
            focused = try? copy(app, attribute: kAXFocusedWindowAttribute as CFString)
        }
        let focusedIndex = members.firstIndex { member in
            guard let focused else { return false }
            return member.processIdentifier == front && CFEqual(member.element, focused)
        }
        var ordered = tokens.filter { handles[$0]?.processIdentifier != front }
        ordered += tokens.enumerated().filter {
            handles[$0.element]?.processIdentifier == front && $0.offset != focusedIndex
        }.map(\.element)
        if let focusedIndex { ordered.append(tokens[focusedIndex]) }
        for token in ordered {
            try ensureSessionOpen(token.sessionID)
            let handle = try validatedHandle(token)
            try performNativeAction(handle.element, action: kAXRaiseAction as CFString)
        }
    }

    /// Close remains cooperative. Keep the exact handle while the application presents a save
    /// sheet, so cancelling that sheet does not lose the pair or select a replacement window.
    func meltClose(_ tokens: [ApplicationWindowToken]) async throws {
        for token in tokens { try ensureSessionOpen(token.sessionID) }
        for token in tokens {
            guard try actionCapabilities(token).canClose else { throw WindowActionError.unsupported }
        }
        for token in tokens {
            let handle = try validatedHandle(token)
            let pid = handle.processIdentifier
            let birth = handle.launchDate
            let activated = await MainActor.run {
                guard !Task.isCancelled, let app = NSRunningApplication(processIdentifier: pid),
                      app.windowControlLaunchDate == birth, !app.isTerminated else { return false }
                return app.activate(options: [])
            }
            guard activated, try actionCapabilities(token).canClose,
                  let button = closeButton(try validatedHandle(token).element) else { throw WindowActionError.unsupported }
            try performNativeAction(button, action: kAXPressAction as CFString)
        }
    }
}
