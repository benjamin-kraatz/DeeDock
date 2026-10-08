import CoreGraphics
import Foundation

/// One on-screen window from `CGWindowList`, which lists windows front to back. Owner and bounds
/// need no permission; titles come from ScreenCaptureKit when Screen Recording is granted.
nonisolated struct HarborScreenWindow: Equatable, Sendable {
    let number: CGWindowID
    let processIdentifier: pid_t
    /// Global Quartz bounds in points.
    let frame: CGRect
    var title: String?
}

/// Turns raw discovery inputs into Harbor windows. Pure, so the Space and permission rules are testable.
///
/// Public APIs expose no Space identity. Harbor treats a window as part of the current Space when
/// `CGWindowList`'s on-screen list holds a window from the same process with the same bounds.
/// Accessibility lists windows on other Spaces too; those find no on-screen partner and are left out.
nonisolated enum HarborDiscoveryProjection {
    /// Windows smaller than this in either dimension are helper or utility surfaces, not documents.
    static let minimumSide: CGFloat = 40

    /// - Parameters:
    ///   - apps: Running regular apps. Windows of other processes are dropped.
    ///   - accessibility: Accessibility summaries, or nil when Accessibility is off or failed.
    ///   - screen: On-screen layer-0 windows, front to back.
    ///   - capturable: Window numbers ScreenCaptureKit can capture, or nil without Screen Recording.
    ///   - makeID: Identity for each window; tests pass a deterministic source.
    static func windows(apps: [HarborRunningApp], accessibility: [ApplicationWindowSummary]?,
                        screen: [HarborScreenWindow], capturable: Set<CGWindowID>?,
                        makeID: () -> UUID = UUID.init) -> [HarborWindow] {
        let apps = Dictionary(apps.map { ($0.processIdentifier, $0) }, uniquingKeysWith: { first, _ in first })
        guard let accessibility else {
            return screen.enumerated().compactMap { index, window in
                guard let app = apps[window.processIdentifier], large(window.frame) else { return nil }
                return HarborWindow(id: makeID(), appID: app.id, processIdentifier: window.processIdentifier,
                                    title: window.title, frame: window.frame, state: .visible, token: nil,
                                    captureID: capturable?.contains(window.number) == true ? window.number : nil,
                                    stackOrder: index)
            }
        }
        return accessibility.enumerated().compactMap { index, summary in
            guard let app = apps[summary.processIdentifier], let frame = summary.frame, large(frame) else { return nil }
            if summary.isMinimized || app.isHidden {
                return HarborWindow(id: makeID(), appID: app.id, processIdentifier: summary.processIdentifier,
                                    title: summary.title, frame: frame, state: summary.isMinimized ? .minimized : .hidden,
                                    token: summary.token, captureID: nil, stackOrder: screen.count + index,
                                    document: summary.document)
            }
            let partners = screen.indices.filter { position in
                let candidate = screen[position]
                return candidate.processIdentifier == summary.processIdentifier && close(candidate.frame, frame)
                    && (candidate.title == nil || summary.title == nil || candidate.title == summary.title)
            }
            // No on-screen partner: another Space, or a window the app keeps off screen.
            guard let front = partners.first else { return nil }
            // Two identical untitled windows cannot be told apart; neither gets a thumbnail.
            let number = partners.count == 1 ? screen[front].number : nil
            return HarborWindow(id: makeID(), appID: app.id, processIdentifier: summary.processIdentifier,
                                title: summary.title ?? screen[front].title, frame: frame, state: .visible,
                                token: summary.token,
                                captureID: number.flatMap { capturable?.contains($0) == true ? $0 : nil },
                                stackOrder: front, document: summary.document)
        }
    }

    private static func large(_ frame: CGRect) -> Bool {
        frame.width >= minimumSide && frame.height >= minimumSide
    }

    /// The same two-point tolerance Window Peek uses to join AX and window-server frames.
    private static func close(_ first: CGRect, _ second: CGRect) -> Bool {
        [first.minX - second.minX, first.minY - second.minY,
         first.width - second.width, first.height - second.height].allSatisfy { abs($0) <= 2 }
    }
}
