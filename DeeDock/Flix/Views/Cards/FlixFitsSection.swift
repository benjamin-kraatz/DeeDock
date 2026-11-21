import SwiftUI

/// "✦ Fits portal.example.com": items for the window that was in front, with the reader chain
/// that found them. Shimmers while the window is read; absent when there is nothing to suggest.
///
/// The card is one view from reading to ready, so its height settles with ``FlixMotion/row`` while
/// the shimmer crossfades into rows that rise one after another. With Reduce Motion the rows
/// crossfade in.
struct FlixFitsSection: View {
    let state: FlixPanelState

    private struct Head: Equatable {
        var label: String
        var chain: FlixReaderChain
        var loading: Bool
    }

    private var head: Head? {
        switch state.intelligence.fits {
        case .hidden: nil
        case .reading(let label, let chain): Head(label: label, chain: chain, loading: true)
        case .ready(let result): state.fitItems.isEmpty ? nil : Head(label: result.windowLabel, chain: result.chain, loading: false)
        }
    }

    var body: some View {
        if let head {
            let rows = head.loading ? [] : state.fitItems
            FlixFitsCard(label: head.label, chain: head.chain, reduceMotion: state.reduceMotion) {
                if head.loading {
                    FlixLoadingRows(reduceMotion: state.reduceMotion)
                        .transition(.opacity)
                }
                ForEach(Array(rows.enumerated()), id: \.element.0.id) { index, pair in
                    row(pair.0, pair.1)
                        .transition(FlixMotion.rise(reduceMotion: state.reduceMotion, index: index))
                }
            }
            .transition(FlixMotion.rise(reduceMotion: state.reduceMotion))
            .animation(state.motion(FlixMotion.row), value: head)
            .animation(state.motion(FlixMotion.row), value: rows.map(\.1.id))
        }
    }

    private func row(_ fit: FlixFit, _ item: FlixItem) -> some View {
        FlixRowView(item: item,
                    context: FlixRowContext(fitPhrase: fit.phrase,
                                            memory: fit.memory ?? state.intelligence.dragReason(
                                                for: item, context: state.frontmost),
                                            conversion: state.conversionChip?(item)),
                    annotation: state.intelligence.annotation(for: item.id),
                    selected: state.selection.contains(item.id),
                    dimmed: state.drag?.itemIDs.contains(item.id) == true,
                    now: state.now, policy: state.readPolicy, reduceMotion: state.reduceMotion,
                    press: { state.press(item.id, command: $0, shift: $1, origin: .fits) },
                    click: { state.click(item.id, command: $0, shift: $1) },
                    open: { state.open([item], origin: .fits) },
                    beginDrag: { view, event in
                        let ids = state.selection.contains(item.id)
                            ? state.navigationOrder.filter(state.selection.contains) : [item.id]
                        state.beginDrag?(ids, view, event, .fits)
                    },
                    menu: { FlixContextMenu.make(for: state) },
                    actions: FlixRowActions(state: state, item: item))
    }
}

/// The Fits card's frame: title, reader chain, and the violet wash around its rows.
private struct FlixFitsCard<Content: View>: View {
    let label: String
    let chain: FlixReaderChain
    let reduceMotion: Bool
    @ViewBuilder var content: Content

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: FlixStyle.cardRadius, style: .continuous)
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 6) {
                FlixSparkle(size: 11)
                Text(.flixFitsTitle(label))
                    .lineLimit(1)
                    .truncationMode(.middle)
                    .layoutPriority(1)
                Spacer(minLength: 6)
                FlixReaderChainLabel(chain: chain)
                    .animation(reduceMotion ? nil : FlixMotion.hover, value: chain)
            }
            .font(.system(size: 11, weight: .semibold))
            .padding(.horizontal, 8)
            .padding(.top, 9)
            .padding(.bottom, 3)
            content
        }
        .padding(.horizontal, 4)
        .padding(.bottom, 4)
        .background(shape.fill(FlixStyle.aiWash).allowsHitTesting(false))
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
                    if index > 0 { Image(systemName: "arrow.right").font(.system(size: 8, weight: .semibold)) }
                    if index < chain.steps.count - 1 {
                        Text(verbatim: Self.name(step)).strikethrough().opacity(0.7)
                    } else {
                        Text(verbatim: Self.name(step)).fontWeight(.bold).foregroundStyle(FlixStyle.aiGradient)
                    }
                }
            }
        }
        .font(.system(size: 10.5, weight: .medium))
        .foregroundStyle(FlixStyle.faint)
        .lineLimit(1)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text(chain.steps.last.map { .flixReadVia(Self.name($0)) } ?? LocalizedStringResource(stringLiteral: "")))
    }

    static func name(_ step: FlixReaderStep) -> String {
        switch step {
        case .accessibility: String(localized: .flixReaderAccessibility)
        case .vision: String(localized: .flixReaderVision)
        case .appleIntelligence: String(localized: .flixReaderAppleIntelligence)
        }
    }
}

#if DEBUG
#Preview("Fits, ready") {
    ScrollView { FlixFitsSection(state: FlixPreviewData.panelState(withIntelligence: true)).padding(.horizontal, 8) }
        .frame(width: 516, height: 200)
}

#Preview("Fits, reading") {
    ScrollView { FlixFitsSection(state: FlixPreviewData.panelState(.fitsLoading)).padding(.horizontal, 8) }
        .frame(width: 516, height: 200)
}

#Preview("Reader chains") {
    VStack(alignment: .trailing, spacing: 8) {
        FlixReaderChainLabel(chain: FlixReaderChain(steps: [.accessibility], succeeded: true))
        FlixReaderChainLabel(chain: FlixReaderChain(steps: [.accessibility, .vision], succeeded: true))
        FlixReaderChainLabel(chain: FlixReaderChain(steps: [.accessibility, .vision, .appleIntelligence], succeeded: true))
    }
    .padding()
}
#endif
