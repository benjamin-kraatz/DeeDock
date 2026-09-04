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

    var body: some View {
        Button { interaction.openFocusSession?() } label: {
            DockIconPresentation(size: size, edge: interaction.layout.edge,
                available: true, running: false, launching: false, keyboardSelected: selected,
                artworkOpacity: DockAppearanceOpacity(settings: interaction.idleFade.settings,
                    idleFraction: interaction.idleFade.fraction, reduceTransparency: reduceTransparency).icons,
                artworkAnimation: interaction.idleFade.animation) {
                if item.session.phase == .running && interaction.exposesContent {
                    TimelineView(.periodic(from: .now, by: 1)) { context in glyph(at: context.date) }
                } else { glyph(at: .now) }
            }
        }
        .buttonStyle(.plain)
        .accessibilityLabel(Text(.focusTileName(item.session.modeName)))
        .accessibilityValue(Text(status))
        .accessibilityHint(Text(.focusTileHint))
        .accessibilityFocused($accessibilityFocused)
        .onChange(of: accessibilityFocused) { _, focused in accessibilityFocus(focused) }
        .onDisappear { accessibilityFocus(false) }
    }

    private var status: LocalizedStringResource {
        switch item.session.phase {
        case .running: .focusRunning
        case .paused: .focusPaused
        case .completed: .focusCompleted
        }
    }
    private func glyph(at date: Date) -> some View {
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
                    Text(verbatim: item.session.timeLabel(at: date)).font(.system(size: size * 0.23, weight: .semibold)).monospacedDigit()
                }.foregroundStyle(.white)
            }
        }
    }
}
