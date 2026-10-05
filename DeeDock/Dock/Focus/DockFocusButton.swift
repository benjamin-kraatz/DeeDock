import SwiftUI

/// A visible running timer updates once per second. Hidden, paused, and completed docks do no ticking.
struct DockFocusButton: View {
    let item: FocusDockItem
    let size: CGFloat
    let selected: Bool
    let interaction: DockInteraction
    let accessibilityFocus: (Bool) -> Void
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    @AccessibilityFocusState private var accessibilityFocused: Bool
    /// Stable start for the one-second timeline. Recreating the schedule from `.now` on each accessibility refresh would skip ticks.
    @State private var timelineAnchor = Date()
    /// Date the running tile last drew. VoiceOver reads remaining time from this without rebuilding the button.
    @State private var readingDate = Date()

    var body: some View {
        Button { interaction.openFocusSession?() } label: {
            DockIconPresentation(size: size, edge: interaction.layout.edge,
                available: true, running: false, launching: false, keyboardSelected: selected,
                artworkOpacity: DockAppearanceOpacity(settings: interaction.idleFade.settings,
                    idleFraction: interaction.idleFade.fraction, reduceTransparency: reduceTransparency).icons,
                artworkAnimation: interaction.idleFade.animation) {
                if item.session.phase == .running && interaction.exposesContent {
                    TimelineView(.periodic(from: timelineAnchor, by: 1)) { context in
                        glyph(at: context.date)
                            .onChange(of: context.date, initial: true) { _, date in
                                // Whole seconds only. A sub-second date on each refresh would republish state in a loop.
                                let drawn = Int(readingDate.timeIntervalSinceReferenceDate)
                                let next = Int(date.timeIntervalSinceReferenceDate)
                                if drawn != next { readingDate = date }
                            }
                    }
                } else { glyph(at: .now) }
            }
        }
        .buttonStyle(.plain)
        .accessibilityLabel(Text(.focusTileName(item.session.modeName)))
        .accessibilityValue(accessibilityValue(at: accessibilityDate))
        .accessibilityHint(Text(.focusTileHint))
        .accessibilityFocused($accessibilityFocused)
        .onChange(of: accessibilityFocused) { _, focused in accessibilityFocus(focused) }
        .onDisappear { accessibilityFocus(false) }
    }

    /// Visible running sessions follow the timeline. Hidden, paused, and completed tiles do not tick.
    private var accessibilityDate: Date {
        item.session.phase == .running && interaction.exposesContent ? readingDate : .now
    }

    private func accessibilityValue(at date: Date) -> Text {
        Text(status) + Text(verbatim: ", \(item.session.spokenRemaining(at: date))")
    }

    private var status: LocalizedStringResource {
        switch item.session.phase {
        case .running: .focusRunning
        case .paused: .focusPaused
        case .completed: .focusCompleted
        }
    }
    @ViewBuilder private func glyph(at date: Date) -> some View {
        if item.bossVictoryID != nil {
            BossFightVictoryGlyph(size: size, exposesContent: interaction.exposesContent)
        } else if item.bossFightEnabled && item.session.phase != .completed {
            BossFightGlyph(session: item.session, date: date, size: size)
        } else {
            normalGlyph(at: date)
        }
    }

    private func normalGlyph(at date: Date) -> some View {
        ZStack {
            RoundedRectangle(cornerRadius: size * 0.23).fill(.teal.gradient)
            Circle().stroke(.white.opacity(0.25), lineWidth: max(2, size * 0.06)).padding(size * 0.1)
            Circle().trim(from: 0, to: item.session.fraction(at: date))
                .stroke(.white, style: StrokeStyle(lineWidth: max(2, size * 0.06), lineCap: .round))
                .rotationEffect(.degrees(-90)).padding(size * 0.1)
            if item.session.phase == .completed {
                Image(systemName: "checkmark").font(.system(size: size * 0.4, weight: .semibold)).foregroundStyle(.white)
                    .symbolEffect(.bounce, options: .nonRepeating, value: reduceMotion ? nil : item.celebrationID)
            } else {
                VStack(spacing: 0) {
                    if item.session.phase == .paused { Image(systemName: "pause.fill").font(.system(size: size * 0.15)) }
                    countdown(at: date)
                }.foregroundStyle(.white)
            }
        }
    }

    /// `MM:SS` already sits inside the progress ring. `H:MM:SS` scales to the ring's inner diameter.
    @ViewBuilder private func countdown(at date: Date) -> some View {
        let label = Text(verbatim: item.session.timeLabel(at: date))
            .font(.system(size: size * 0.23, weight: .semibold)).monospacedDigit()
        if item.session.showsHours(at: date) {
            label.lineLimit(1).minimumScaleFactor(0.55)
                .frame(maxWidth: size * 0.8 - max(2, size * 0.06))
        } else {
            label
        }
    }
}
