import SwiftUI

/// "✦ Fits portal.example.com": items for the window that was in front, with the reader chain
/// that found them. Shimmers while the window is read; absent when there is nothing to suggest.
struct FlixFitsSection: View {
    let state: FlixPanelState

    var body: some View {
        switch state.intelligence.fits {
        case .hidden:
            EmptyView()
        case .reading(let label, let chain):
            container(label: label, chain: chain) {
                FlixShimmer(reduceMotion: state.reduceMotion)
                FlixShimmer(reduceMotion: state.reduceMotion).opacity(0.6)
            }
        case .ready(let result):
            let rows = state.fitItems
            if !rows.isEmpty {
                container(label: result.windowLabel, chain: result.chain) {
                    ForEach(rows, id: \.0.id) { fit, item in
                        FlixRowView(item: item,
                                    context: FlixRowContext(fitPhrase: fit.phrase,
                                                            memory: fit.memory ?? state.intelligence.dragReason(
                                                                for: item, context: state.frontmost)),
                                    annotation: state.intelligence.annotation(for: item.id),
                                    selected: state.selection.contains(item.id),
                                    dimmed: state.drag?.itemIDs.contains(item.id) == true,
                                    now: state.now, policy: state.readPolicy,
                                    press: { state.press(item.id, command: $0, shift: $1) },
                                    click: { state.click(item.id, command: $0, shift: $1) },
                                    open: { state.open([item]) },
                                    beginDrag: { view, event in
                                        let ids = state.selection.contains(item.id)
                                            ? state.navigationOrder.filter(state.selection.contains) : [item.id]
                                        state.beginDrag?(ids, view, event)
                                    },
                                    menu: { FlixContextMenu.make(for: state) })
                    }
                }
            }
        }
    }

    private func container<Content: View>(label: String, chain: FlixReaderChain,
                                          @ViewBuilder content: () -> Content) -> some View {
        let shape = RoundedRectangle(cornerRadius: 12, style: .continuous)
        return VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 6) {
                FlixSparkle(size: 11)
                Text(.flixFitsTitle(label))
                    .lineLimit(1)
                Spacer(minLength: 6)
                FlixReaderChainLabel(chain: chain)
            }
            .font(.system(size: 11, weight: .semibold))
            .padding(.horizontal, 8)
            .padding(.top, 9)
            .padding(.bottom, 3)
            content()
        }
        .padding(.horizontal, 4)
        .padding(.bottom, 4)
        .background(shape.fill(LinearGradient(colors: [FlixStyle.aiViolet.opacity(0.10), Color.blue.opacity(0.07)],
                                              startPoint: .topLeading, endPoint: .bottomTrailing)).allowsHitTesting(false))
        .overlay(shape.strokeBorder(FlixStyle.aiStroke, lineWidth: 0.5).allowsHitTesting(false))
        .padding(.top, 6)
        .padding(.bottom, 4)
        .accessibilityElement(children: .contain)
        .accessibilityLabel(Text(.flixFitsTitle(label)))
    }
}

/// "read via Accessibility", or "~~Accessibility~~ → Vision" when an earlier reader found too little.
struct FlixReaderChainLabel: View {
    let chain: FlixReaderChain

    var body: some View {
        HStack(spacing: 4) {
            if chain.steps.count <= 1, let only = chain.steps.first {
                Text(.flixReadVia(Self.name(only)))
            } else {
                ForEach(Array(chain.steps.enumerated()), id: \.offset) { index, step in
                    if index > 0 { Text(verbatim: "→") }
                    if index < chain.steps.count - 1 {
                        Text(verbatim: Self.name(step)).strikethrough().opacity(0.7)
                    } else {
                        Text(verbatim: Self.name(step)).foregroundStyle(FlixStyle.aiGradient)
                    }
                }
            }
        }
        .font(.system(size: 10.5, weight: .medium))
        .foregroundStyle(.secondary)
        .lineLimit(1)
    }

    static func name(_ step: FlixReaderStep) -> String {
        switch step {
        case .accessibility: String(localized: .flixReaderAccessibility)
        case .vision: String(localized: .flixReaderVision)
        case .appleIntelligence: String(localized: .flixReaderAppleIntelligence)
        }
    }
}
