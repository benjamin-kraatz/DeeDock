import SwiftUI

/// Frequent actions remain visible; secondary actions move into the overflow on narrow pairs.
struct AppMeltToolbar: View {
    @Bindable var pair: AppMeltPair
    let controller: AppMeltController

    var body: some View {
        HStack(spacing: 10) {
            if let tools = pair.finderTools {
                AppMeltToolbarGroup {
                    MeltFinderToolsButton(state: tools).disabled(pair.busy || pair.isDragging)
                }
            }
            AppMeltToolbarGroup {
                if let replacement = pair.replacement {
                    AppMeltReplacementButton(state: replacement, pair: pair)
                }
                toolbarButton(.meltCompare, symbol: "sparkles") { controller.compare(pair) }
                toolbarButton(.meltSwap, symbol: "arrow.left.arrow.right") { controller.swapSides(pair) }
            }
            AppMeltToolbarGroup {
                Button { pair.layoutPopover.toggle() } label: {
                    HStack(spacing: 7) {
                        Image(systemName: "rectangle.split.2x1")
                        Image(systemName: "chevron.down").font(.system(size: 10, weight: .semibold))
                    }
                    .frame(width: 52, height: 32)
                }
                .buttonStyle(AppMeltToolbarButtonStyle(selected: pair.layoutPopover))
                .help(Text(.meltTiles)).accessibilityLabel(Text(.meltTiles))
                .disabled(!pair.canChangeLayout)
                .popover(isPresented: $pair.layoutPopover, arrowEdge: .bottom) {
                    AppMeltTilePicker(pair: pair, controller: controller)
                }
            }
            ViewThatFits(in: .horizontal) {
                AppMeltToolbarGroup {
                    toolbarButton(pair.fittedFrom == nil ? .meltFit : .meltRestoreSize,
                        symbol: "arrow.up.left.and.arrow.down.right", selected: pair.fittedFrom != nil) {
                        controller.toggleFit(pair)
                    }
                    toolbarButton(.meltUndoLayout, symbol: "arrow.uturn.backward") { controller.undo(pair) }
                        .disabled(pair.undoLayout == nil)
                    Rectangle().fill(.primary.opacity(0.2)).frame(width: 1, height: 20)
                        .padding(.horizontal, 3).accessibilityHidden(true)
                    toolbarButton(.meltUnpair, symbol: "rectangle.on.rectangle.slash") { controller.unpair(pair) }
                    overflow
                }
                AppMeltToolbarGroup { overflow }
            }
        }
        .fixedSize(horizontal: false, vertical: true)
    }

    private func toolbarButton(_ title: LocalizedStringResource, symbol: String, selected: Bool = false,
                               action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Label(title, systemImage: symbol).labelStyle(.iconOnly).frame(width: 38, height: 32)
        }
        .buttonStyle(AppMeltToolbarButtonStyle(selected: selected))
        .help(Text(title)).disabled(!pair.canChangeLayout)
    }

    private var overflow: some View {
        AppMeltOverflowButton(pair: pair, controller: controller)
            .frame(width: 38, height: 32)
            .help(Text(.meltPairActions))
    }

}

private struct AppMeltTilePicker: View {
    let pair: AppMeltPair
    let controller: AppMeltController
    @State private var customRatio = 0.5
    private let ratios = [0.25, 1.0 / 3, 0.5, 2.0 / 3, 0.75]

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text(.meltTiles).font(.headline)
            HStack(spacing: 8) {
                ForEach(ratios, id: \.self) { ratio in
                    Button {
                        pair.layoutPopover = false
                        controller.setProportion(pair, ratio: ratio)
                    } label: {
                        VStack(spacing: 6) {
                            HStack(spacing: 2) {
                                RoundedRectangle(cornerRadius: 2).frame(width: 48 * ratio)
                                RoundedRectangle(cornerRadius: 2).opacity(0.4).frame(width: 48 * (1 - ratio))
                            }.frame(height: 26)
                            Text(verbatim: label(ratio)).font(.caption)
                        }
                        .padding(5)
                    }
                    .buttonStyle(.bordered)
                    .accessibilityLabel(Text(.meltSplitPercent(Int((ratio * 100).rounded()))))
                }
            }
            Slider(value: $customRatio, in: 0.25...0.75) { Text(.meltProportions) }
            HStack {
                Text(.meltSplitPercent(Int((customRatio * 100).rounded()))).foregroundStyle(.secondary)
                Spacer()
                Button(.meltApplyLayout) {
                    pair.layoutPopover = false
                    controller.setProportion(pair, ratio: customRatio)
                }.buttonStyle(.borderedProminent)
            }
        }
        .padding(16)
        .disabled(!pair.canChangeLayout)
        .onAppear { customRatio = min(0.75, max(0.25, pair.ratio)) }
    }

    private func label(_ ratio: Double) -> String {
        if ratio == 1.0 / 3 { return "⅓ / ⅔" }
        if ratio == 2.0 / 3 { return "⅔ / ⅓" }
        return "\(Int((ratio * 100).rounded()))/\(Int(((1 - ratio) * 100).rounded()))"
    }
}
