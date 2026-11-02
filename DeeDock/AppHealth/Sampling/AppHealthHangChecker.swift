import ApplicationServices
import Foundation

/// One responsiveness check.
nonisolated struct AppHealthHangCheck: Sendable, Equatable {
    let result: AppHealthHangResult
    let milliseconds: Int
}

/// Asks an app whether it responds. The live implementation is `AppHealthHangChecker`; tests pass a fake.
nonisolated protocol AppHealthHangChecking: Sendable {
    func check(pid: pid_t) async -> AppHealthHangCheck
}

/// Checks responsiveness by asking an app's Accessibility element for its role with a 0.5 s timeout.
///
/// Callers run it only when `AXIsProcessTrusted()` is already true; App Health never asks for Accessibility.
/// Accessibility calls block until the app answers or the timeout passes, so they run one at a time on a dedicated
/// serial utility queue, never on the main thread or the cooperative pool. A started check cannot be interrupted;
/// the timeout bounds it, and the caller checks for cancellation between apps.
nonisolated final class AppHealthHangChecker: AppHealthHangChecking {
    /// Messaging timeout per check, in seconds.
    static let timeout: Float = 0.5

    private let queue = DispatchQueue(label: "de.benjaminkraatz.DeeDock.AppHealth.hangCheck", qos: .utility)

    init() {}

    func check(pid: pid_t) async -> AppHealthHangCheck {
        await withCheckedContinuation { continuation in
            queue.async { continuation.resume(returning: Self.probe(pid)) }
        }
    }

    private static func probe(_ pid: pid_t) -> AppHealthHangCheck {
        let element = AXUIElementCreateApplication(pid)
        AXUIElementSetMessagingTimeout(element, timeout)
        var value: CFTypeRef?
        let start = clock_gettime_nsec_np(CLOCK_UPTIME_RAW)
        let error = AXUIElementCopyAttributeValue(element, kAXRoleAttribute as CFString, &value)
        let milliseconds = Int((clock_gettime_nsec_np(CLOCK_UPTIME_RAW) &- start) / 1_000_000)
        let result: AppHealthHangResult = switch error {
        case .success: .ok
        case .cannotComplete: .timeout
        default: .error
        }
        return AppHealthHangCheck(result: result, milliseconds: milliseconds)
    }
}

/// Which apps get a responsiveness check this tick. Pure.
nonisolated enum AppHealthHangCandidates {
    /// At most this many checks per tick, so a tick stays well under its interval even if every check times out.
    static let limit = 4
    /// CPU use at or above which a regular app is checked even when it is not in front.
    static let busyPercent = 50.0

    struct Candidate: Sendable, Equatable {
        let app: String
        let kind: AppHealthAppKind
        let cpuPercent: Double
        let frontmost: Bool
    }

    /// Regular apps that are frontmost, busy, or failed their last check. Frontmost first, then apps that failed
    /// last time, then the busiest.
    ///
    /// - Parameter failedLastCheck: Apps whose most recent check was not `ok`.
    static func select(_ candidates: [Candidate], failedLastCheck: Set<String>) -> [String] {
        candidates
            .filter { $0.kind == .regular
                && ($0.frontmost || $0.cpuPercent >= busyPercent || failedLastCheck.contains($0.app)) }
            .sorted { lhs, rhs in
                if lhs.frontmost != rhs.frontmost { return lhs.frontmost }
                let lhsFailed = failedLastCheck.contains(lhs.app), rhsFailed = failedLastCheck.contains(rhs.app)
                if lhsFailed != rhsFailed { return lhsFailed }
                if lhs.cpuPercent != rhs.cpuPercent { return lhs.cpuPercent > rhs.cpuPercent }
                return lhs.app < rhs.app
            }
            .prefix(limit)
            .map(\.app)
    }
}
