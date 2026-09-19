import AppKit

extension AccessibilityApplicationWindowService {
    func meltIsPaired(_ token: ApplicationWindowToken, existing: [ApplicationWindowToken]) throws -> Bool {
        let proposed = try validatedHandle(token, allowRetainedWindow: true).element
        return existing.contains { other in
            guard let handle = try? validatedHandle(other, allowRetainedWindow: true) else { return false }
            return CFEqual(proposed, handle.element)
        }
    }

    /// Copy a validated handle into the pair's lifetime before the chooser discards its session.
    func meltAdopt(_ token: ApplicationWindowToken, sessionID: UUID) throws -> ApplicationWindowSummary {
        let handle = try validatedHandle(token, allowRetainedWindow: true)
        let adopted = ApplicationWindowToken(sessionID: sessionID, id: UUID())
        handles[adopted] = handle
        do { return try meltSummary(adopted) }
        catch { handles[adopted] = nil; throw error }
    }

    /// Activation follows an explicit replacement only, never a passive focus notification.
    func meltActivateReplacement(_ token: ApplicationWindowToken) async throws {
        let handle = try validatedHandle(token)
        let pid = handle.processIdentifier
        let birth = handle.launchDate
        let activated = await MainActor.run {
            guard !Task.isCancelled, let app = NSRunningApplication(processIdentifier: pid),
                  app.windowControlLaunchDate == birth, !app.isTerminated else { return false }
            return app.activate(options: [])
        }
        guard activated else { throw WindowActionError.stale }
    }

    func meltRelease(_ token: ApplicationWindowToken) {
        handles[token] = nil
        undoFrames[token] = nil
    }
}
