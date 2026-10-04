import SwiftUI

/// Shows, side by side, what DOKK shares and what stays on the Mac.
///
/// The stage is a demonstration and hidden from assistive technology like every other stage;
/// the step's summary says the same thing in a sentence. Rows arrive one after another so the
/// two lists read as an answer being given, and Reduce Motion shows them all at once.
struct OnboardingAnalyticsStage: View {
    /// Previews and the surrounding tour can pass an explicit value; the stage otherwise
    /// follows the system setting.
    var reduceMotionOverride: Bool? = nil
    @Environment(\.accessibilityReduceMotion) private var systemReduceMotion
    private var reduceMotion: Bool { reduceMotionOverride ?? systemReduceMotion }
    /// How many rows are visible so far, counted across both lists.
    @State private var revealed = 0

    private var total: Int { AnalyticsDisclosure.collected.count + AnalyticsDisclosure.neverCollected.count }

    var body: some View {
        HStack(alignment: .top, spacing: 16) {
            OnboardingAnalyticsList(title: .analyticsCollectedTitle, symbol: "checkmark.circle.fill", tint: .green,
                                    items: AnalyticsDisclosure.collected, offset: 0, revealed: revealed)
            OnboardingAnalyticsList(title: .analyticsNeverCollectedTitle, symbol: "lock.circle.fill", tint: .orange,
                                    items: AnalyticsDisclosure.neverCollected,
                                    offset: AnalyticsDisclosure.collected.count, revealed: revealed)
        }
        .padding(.horizontal, 26)
        .task(id: reduceMotion) { await reveal() }
    }

    /// One task while the page is on screen; SwiftUI cancels it when the page leaves.
    private func reveal() async {
        guard !reduceMotion else {
            revealed = total
            return
        }
        revealed = 0
        for index in 1...total {
            try? await Task.sleep(for: .milliseconds(index == 1 ? 250 : 140))
            guard !Task.isCancelled else { return }
            withAnimation(.smooth(duration: 0.35)) { revealed = index }
        }
    }
}

private struct OnboardingAnalyticsList: View {
    let title: LocalizedStringResource
    let symbol: String
    let tint: Color
    let items: [AnalyticsDisclosure.Item]
    /// Position of this list's first row in the reveal order.
    let offset: Int
    let revealed: Int

    var body: some View {
        VStack(alignment: .leading, spacing: 9) {
            Label { Text(title).font(.headline) } icon: {
                Image(systemName: symbol).foregroundStyle(tint)
            }
            ForEach(Array(items.enumerated()), id: \.element.id) { index, item in
                let isVisible = revealed > offset + index
                Label { Text(item.text) } icon: {
                    Image(systemName: item.symbol).foregroundStyle(tint)
                }
                .font(.callout)
                .fixedSize(horizontal: false, vertical: true)
                .opacity(isVisible ? 1 : 0)
                .offset(y: isVisible ? 0 : 6)
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(.background.secondary.opacity(0.7), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 14, style: .continuous).strokeBorder(tint.opacity(0.25), lineWidth: 0.5)
        }
        .padding(.vertical, 24)
    }
}

#if DEBUG
#Preview("Usage data stage") {
    OnboardingStage(tint: .teal) { OnboardingAnalyticsStage() }
        .padding(28).frame(width: 700)
}

#Preview("Usage data stage — Reduce Motion, dark") {
    OnboardingStage(tint: .teal) { OnboardingAnalyticsStage(reduceMotionOverride: true) }
        .padding(28).frame(width: 700)
        .preferredColorScheme(.dark)
}
#endif
