import SwiftUI

/// Lookout's progress in Settings: at a glance, is it running, how far is it, how much is left, is it done, or why
/// is it waiting. A ring beside a title and a line of numbers, then the files by kind, then what was skipped.
///
/// The summary is one accessibility element ("Lookout is reading files", "62 %, 3,210 of 5,202 files, about 6
/// minutes left"); Pause/Resume and the skipped-files disclosure stay their own elements. `pause` and `resume` are
/// optional: without them no button is shown.
struct LookoutProgressCard: View {
    let progress: LookoutProgressDisplay
    /// Pauses reading (shown while counting or reading).
    var pause: (() -> Void)?
    /// Resumes reading after the person paused it (shown only for `.paused(reason: .userPaused)`).
    var resume: (() -> Void)?
    var reduceMotion = HubFilesMotion.reduceMotion
    /// "Now" for "finished at 10:41" versus "finished yesterday"; previews and tests pin it.
    var now: Date = .now

    var body: some View {
        SettingsCard {
            LookoutProgressSummaryRow(progress: progress, pause: pause, resume: resume, reduceMotion: reduceMotion,
                                      now: now)
            if progress.kinds.contains(where: { $0.value.total > 0 }) {
                LookoutProgressKindsRow(kinds: progress.kinds, reduceMotion: reduceMotion)
            }
            if progress.hasProblems {
                LookoutProgressProblemsRow(skipped: progress.skipped, failed: progress.failed,
                                           problems: progress.problems, reduceMotion: reduceMotion)
            }
        }
        .animation(reduceMotion ? nil : HubStyle.motion, value: progress.phase)
        .animation(reduceMotion ? nil : HubStyle.motion, value: progress.hasProblems)
    }
}

/// The card's first row: the ring, the title with its breathing dot while Lookout works, the numbers, and
/// Pause/Resume. A soft Lookout wash from the leading edge (the promo card's) marks it as Lookout's.
private struct LookoutProgressSummaryRow: View {
    let progress: LookoutProgressDisplay
    let pause: (() -> Void)?
    let resume: (() -> Void)?
    let reduceMotion: Bool
    let now: Date

    @Environment(\.colorScheme) private var scheme
    @Environment(\.locale) private var locale

    var body: some View {
        let copy = LookoutProgressCopy(progress: progress, locale: locale, now: now)
        HStack(alignment: .center, spacing: 14) {
            LookoutProgressGauge(progress: progress, reduceMotion: reduceMotion)
            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 7) {
                    if progress.isActive {
                        LookoutProgressPulse(color: LookoutTheme(scheme).accent, reduceMotion: reduceMotion)
                    }
                    Text(verbatim: copy.title)
                        .font(.system(size: 15, weight: .semibold))
                        .lineLimit(2)
                }
                Text(verbatim: copy.subtitle)
                    .font(.system(size: 12.5))
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
                    .contentTransition(reduceMotion ? .identity : .numericText())
                    .fixedSize(horizontal: false, vertical: true)
                if let detail = copy.detail {
                    Text(verbatim: detail)
                        .font(.system(size: 11.5))
                        .foregroundStyle(.tertiary)
                        .monospacedDigit()
                        .contentTransition(reduceMotion ? .identity : .numericText())
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .animation(reduceMotion ? nil : .easeOut(duration: 0.3), value: copy.subtitle)
            .animation(reduceMotion ? nil : .easeOut(duration: 0.3), value: copy.detail)
            .frame(maxWidth: .infinity, alignment: .leading)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(Text(verbatim: copy.accessibilityLabel))
            .accessibilityValue(Text(verbatim: copy.accessibilityValue))
            button
        }
        .padding(.horizontal, SettingsMetrics.rowInset)
        .padding(.vertical, 13)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(alignment: .leading) {
            LinearGradient(stops: [.init(color: LookoutTheme(scheme).accentSoft, location: 0),
                                   .init(color: .clear, location: 0.55)],
                           startPoint: UnitPoint(x: 0, y: 0.2), endPoint: UnitPoint(x: 1, y: 0.8))
                .opacity(washOpacity)
                .animation(reduceMotion ? nil : .easeOut(duration: 0.4), value: washOpacity)
        }
    }

    /// The wash is strongest while Lookout works, gone once it's done.
    private var washOpacity: Double {
        switch progress.phase {
        case .counting, .reading: 1
        case .paused, .waitingForDrive, .failed: 0.5
        case .upToDate: 0
        }
    }

    @ViewBuilder private var button: some View {
        if progress.isActive, let pause {
            Button(.lookoutProgressPause, action: pause)
                .controlSize(.small)
        } else if progress.phase == .paused(reason: .userPaused), let resume {
            Button(.lookoutProgressResume, action: resume)
                .controlSize(.small)
        }
    }
}

/// The 7 pt dot before the title while Lookout works: the status chip's, breathing down to 35 % and back every
/// 1.6 s, still under Reduce Motion.
private struct LookoutProgressPulse: View {
    let color: Color
    let reduceMotion: Bool

    @State private var dim = false

    var body: some View {
        Circle()
            .fill(color)
            .frame(width: 7, height: 7)
            .opacity(dim ? 0.35 : 1)
            .onAppear { startBreathing() }
            .onChange(of: reduceMotion) { startBreathing() }
            .accessibilityHidden(true)
    }

    private func startBreathing() {
        guard !reduceMotion else {
            var transaction = Transaction(animation: nil)
            transaction.disablesAnimations = true
            withTransaction(transaction) { dim = false }
            return
        }
        withAnimation(.easeInOut(duration: 0.8).repeatForever(autoreverses: true)) { dim = true }
    }
}

/// The summary row's words for a state, in a locale: the title, the line of numbers, an optional third line, and
/// what VoiceOver reads. Built once per body so the row and its accessibility agree.
struct LookoutProgressCopy: Equatable {
    let title: String
    let subtitle: String
    let detail: String?
    let accessibilityLabel: String
    let accessibilityValue: String

    init(progress: LookoutProgressDisplay, locale: Locale, now: Date) {
        typealias F = LookoutProgressFormatting
        let percent = progress.fraction.map { F.percent($0, locale: locale) }
        let count = F.countLine(done: progress.done, total: progress.total, locale: locale)
        let left = progress.remaining.map { F.localized(.lookoutStatusIndexingRemaining($0), locale) }

        switch progress.phase {
        case .counting:
            title = F.localized(.lookoutProgressCounting, locale)
            subtitle = F.countingLine(total: progress.total, locale: locale)
            detail = nil
            accessibilityLabel = F.localized(.lookoutProgressSpokenCounting, locale)
            accessibilityValue = subtitle

        case .reading:
            let time = progress.estimatedRemaining.map { F.timeLeft($0, locale: locale) }
                ?? F.localized(.lookoutProgressEstimating, locale)
            title = F.localized(.lookoutStatusIndexing, locale)
            subtitle = Self.joined(count, time)
            detail = progress.filesPerSecond.map { F.rate($0, locale: locale) }
            accessibilityLabel = F.localized(.lookoutProgressSpokenReading, locale)
            let spokenTime = progress.estimatedRemaining.map { F.timeLeft($0, locale: locale, wide: true) }
            accessibilityValue = Self.joined(percent, count, spokenTime, separator: ", ")

        case .upToDate:
            let finished = progress.lastCompleted.map { F.finished($0, now: now, locale: locale) }
            title = F.localized(.lookoutProgressUpToDate, locale)
            subtitle = Self.joined(F.localized(.lookoutSetupFiles(progress.done), locale), finished)
            detail = nil
            accessibilityLabel = F.localized(.lookoutProgressSpokenUpToDate, locale)
            accessibilityValue = subtitle

        case .paused(let reason):
            title = F.localized(.lookoutStatusPaused, locale)
            subtitle = Self.joined(F.localized(reason.title, locale), left)
            detail = progress.total == nil ? nil : count
            accessibilityLabel = F.localized(.lookoutProgressSpokenPaused, locale)
            accessibilityValue = Self.joined(F.localized(reason.title, locale), percent, count, separator: ", ")

        case .waitingForDrive(let name):
            title = F.localized(.lookoutProgressWaitingForDrive(name), locale)
            subtitle = F.localized(.lookoutProgressWaitingForDriveDetail, locale)
            detail = left
            accessibilityLabel = F.localized(.lookoutProgressSpokenWaiting, locale)
            accessibilityValue = Self.joined(name, percent, left, separator: ", ")

        case .failed(let message):
            title = F.localized(.lookoutStatusFailed, locale)
            subtitle = message
            detail = progress.total == nil ? nil : count
            accessibilityLabel = F.localized(.lookoutStatusFailed, locale)
            accessibilityValue = Self.joined(message, count, separator: ", ")
        }
    }

    private static func joined(_ parts: String?..., separator: String = " · ") -> String {
        parts.compactMap { $0 }.joined(separator: separator)
    }
}

extension LookoutProgressDisplay.PauseReason {
    /// Why reading waits, the status chip's words.
    var title: LocalizedStringResource {
        switch self {
        case .lowPowerMode: .lookoutPauseLowPowerMode
        case .thermal: .lookoutPauseWarm
        case .onBattery: .lookoutPauseOnBattery
        case .userPaused: .lookoutPauseUser
        }
    }
}

// MARK: - Previews

#if DEBUG
/// Every sample in a column, the way the renders show them.
struct LookoutProgressCardGallery: View {
    var reduceMotion = false
    var now: Date = .now

    var body: some View {
        VStack(spacing: SettingsMetrics.cardSpacing) {
            ForEach(LookoutProgressDisplay.Sample.all(now: now), id: \.name) { sample in
                LookoutProgressCard(progress: sample.display, pause: {}, resume: {}, reduceMotion: reduceMotion,
                                    now: now)
            }
        }
        .frame(width: SettingsMetrics.columnWidth)
        .padding(SettingsMetrics.pageInset)
    }
}

#Preview("Reading · light") {
    LookoutProgressCard(progress: .Sample.readingMid, pause: {}, resume: {})
        .frame(width: SettingsMetrics.columnWidth)
        .padding(SettingsMetrics.pageInset)
}

#Preview("Gallery · dark") {
    ScrollView { LookoutProgressCardGallery() }
        .preferredColorScheme(.dark)
}

#Preview("Gallery · German, Reduce Motion") {
    ScrollView { LookoutProgressCardGallery(reduceMotion: true) }
        .environment(\.locale, Locale(identifier: "de"))
}
#endif
