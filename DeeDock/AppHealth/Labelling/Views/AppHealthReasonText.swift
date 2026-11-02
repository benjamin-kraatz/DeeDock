import Foundation

/// The one-line, localized explanation under a prompt's question, built from what the rule saw.
///
/// A prompt shows one line even when several flags held. The order favours what a person can confirm at a glance:
/// a failed responsiveness check, then a spin, then memory growth, then wake-ups.
enum AppHealthReasonText {
    static func line(for candidate: AppHealthPromptCandidate) -> String {
        line(trigger: candidate.trigger, reasons: candidate.reasons, evidence: candidate.evidence)
    }

    static func line(trigger: AppHealthPromptTrigger, reasons: [AppHealthPromptReason],
                     evidence: AppHealthSuspicionEvidence) -> String {
        guard trigger == .rule else { return String(localized: .appHealthReasonOrdinary) }
        let flags = Set(reasons)
        if flags.contains(.hang) { return String(localized: .appHealthReasonHang) }
        if flags.contains(.cpu), let cpu = evidence.meanCPUPercent, let seconds = evidence.shortWindowSeconds,
           flags.contains(.background) || flags.contains(.idleUser) {
            let cpuText = percent(cpu), durationText = minutes(seconds)
            return flags.contains(.background)
                ? String(localized: .appHealthReasonSpinBackground(cpu: cpuText, duration: durationText))
                : String(localized: .appHealthReasonSpinIdle(cpu: cpuText, duration: durationText))
        }
        if flags.contains(.memory), let growth = evidence.memoryGrowth, let seconds = evidence.longWindowSeconds {
            return String(localized: .appHealthReasonMemory(
                amount: ByteCountFormatter.string(fromByteCount: growth, countStyle: .memory),
                duration: minutes(seconds)))
        }
        if flags.contains(.wakeups), let rate = evidence.meanWakeupsPerSecond {
            return String(localized: .appHealthReasonWakeups(count: Int(rate.rounded()).formatted()))
        }
        return String(localized: .appHealthReasonOrdinary)
    }

    /// CPU as Activity Monitor shows it, where 100 % is one core: "140 %".
    static func percent(_ cpuPercent: Double) -> String {
        (cpuPercent / 100).formatted(.percent.precision(.fractionLength(0)))
    }

    /// A window length in whole minutes, such as "3 minutes".
    static func minutes(_ seconds: Double) -> String {
        let minutes = max(1, Int((seconds / 60).rounded()))
        return Duration.seconds(minutes * 60).formatted(.units(allowed: [.minutes], width: .wide))
    }
}
