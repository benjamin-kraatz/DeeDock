import AppKit

/// Owns search-only AX sessions. Discovery reads metadata, never screenshots or window text.
actor WindowSearchService {
    private let windows: any ApplicationWindowServicing = AccessibilityApplicationWindowService(maximumWindows: WindowSearchMatcher.maximumSources)
    private let thumbnails: any WindowThumbnailServicing = ScreenCaptureWindowThumbnailService()

    func discover() async throws -> [WindowSearchSource] {
        await windows.stop()
        let apps = await MainActor.run {
            Array(NSWorkspace.shared.runningApplications.filter {
                $0.activationPolicy == .regular && !$0.isTerminated
                    && $0.processIdentifier != ProcessInfo.processInfo.processIdentifier
            }.prefix(64)).map {
                WindowSearchSource(id: UUID(), applicationName: String(($0.localizedName ?? "").prefix(512)),
                    processIdentifier: $0.processIdentifier, launchDate: $0.launchDate,
                    window: nil, candidate: nil)
            }
        }
        let processes = apps.map { ApplicationProcessSnapshot(processIdentifier: $0.processIdentifier, isHidden: false, isActive: false) }
        let fallbackSession = UUID()
        let fallbackWindows = (try? await thumbnails.discover(processes: processes, sessionID: fallbackSession)) ?? []
        try Task.checkCancellation()
        var sources: [WindowSearchSource] = []
        for app in apps {
            try Task.checkCancellation()
            let process = ApplicationProcessSnapshot(processIdentifier: app.processIdentifier, isHidden: false, isActive: false)
            let session = UUID()
            let summaries = (try? await windows.discover(processes: [process], sessionID: session)) ?? []
            try Task.checkCancellation()
            if summaries.isEmpty {
                // ScreenCaptureKit enumeration is metadata-only and preflights consent. It does not prompt.
                let fallback = Array(fallbackWindows.filter { $0.processIdentifier == app.processIdentifier }
                    .prefix(WindowSearchMatcher.maximumSources - sources.count))
                sources.append(contentsOf: fallback.isEmpty ? [app] : fallback.map {
                    WindowSearchSource(id: $0.token.id, applicationName: app.applicationName,
                        processIdentifier: app.processIdentifier, launchDate: app.launchDate,
                        window: nil, candidate: WindowContextCandidate(id: 0, processIdentifier: app.processIdentifier,
                            applicationName: app.applicationName, bundleIdentifier: nil, title: $0.title,
                            frame: $0.frame ?? .zero))
                })
            } else {
                sources.append(contentsOf: summaries.prefix(WindowSearchMatcher.maximumSources - sources.count).map {
                    WindowSearchSource(id: $0.token.id, applicationName: app.applicationName,
                        processIdentifier: app.processIdentifier, launchDate: app.launchDate, window: $0, candidate: nil)
                })
            }
            if sources.count >= WindowSearchMatcher.maximumSources { break }
        }
        return Array(sources.prefix(WindowSearchMatcher.maximumSources))
    }

    /// Revalidate the process lifetime and resolve captured windows conservatively before activation.
    func activate(_ source: WindowSearchSource) async throws {
        let alive = await MainActor.run {
            guard let app = NSRunningApplication(processIdentifier: source.processIdentifier), !app.isTerminated else { return false }
            return app.launchDate == source.launchDate
        }
        guard alive else { throw ApplicationWindowServiceError.applicationUnavailable }
        try Task.checkCancellation()
        if let window = source.window {
            try await windows.selectWindow(window.token)
        } else if let candidate = source.candidate, candidate.id != 0 {
            // A reused window number or changed title must not silently redirect the result.
            let current = try await ScreenCaptureWindowContextService().discover()
            guard current.contains(where: { $0.id == candidate.id && $0.processIdentifier == candidate.processIdentifier
                && $0.title == candidate.title && $0.bundleIdentifier == candidate.bundleIdentifier }) else {
                throw ApplicationWindowServiceError.windowUnavailable
            }
            let session = UUID()
            defer { Task { await windows.discard(sessionID: session) } }
            let summaries = try await windows.discover(processes: [ApplicationProcessSnapshot(
                processIdentifier: source.processIdentifier, isHidden: false, isActive: false)], sessionID: session)
            let matches = summaries.filter { $0.title == candidate.title && $0.frame == candidate.frame }
            guard matches.count == 1, let match = matches.first else { throw ApplicationWindowServiceError.windowUnavailable }
            try Task.checkCancellation()
            try await windows.selectWindow(match.token)
        } else {
            try Task.checkCancellation()
            let activated = await MainActor.run {
                NSRunningApplication(processIdentifier: source.processIdentifier)?.activate(options: []) == true
            }
            if !activated { throw ApplicationWindowServiceError.applicationUnavailable }
        }
    }

    func stop() async { await windows.stop(); await thumbnails.stop() }
}
