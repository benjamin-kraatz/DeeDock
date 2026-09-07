import SwiftUI

/// Step one: the two slots, and the picker that fills them.
struct FusionSelectionView: View {
    let state: FusionState
    @Environment(\.fusionMotion) private var motion

    private var chosenIDs: Set<CGWindowID> { Set(state.sources.map(\.id)) }

    var body: some View {
        VStack(alignment: .leading, spacing: FusionMetrics.section) {
            FusionSection(.fusionSelectionTitle, symbol: "square.on.square.dashed") {
                // Hidden once both slots are full: with nothing to replace, picking would only
                // report that the selection is full.
                if state.sources.count < 2 || state.showingPicker {
                    Button(.fusionChooseWindows, systemImage: "arrow.clockwise") {
                        state.pick(replacing: state.replacingID)
                    }
                    .buttonStyle(.borderless).controlSize(.small)
                    .disabled(state.isBusy)
                }
            } content: {
                slots
            }
            if state.showingPicker {
                FusionWindowPicker(candidates: state.candidates, chosenIDs: chosenIDs,
                                   disabled: state.isBusy, select: { state.select($0) },
                                   close: { state.closePicker() })
                    .transition(.opacity.combined(with: .move(edge: .top)))
            }
            FusionNotice(.fusionSelectionHelp)
        }
        .animation(motion.pop, value: state.sources.map(\.id))
        .animation(motion.step, value: state.showingPicker)
    }

    /// Side by side while the tray is wide enough for two readable cards, stacked otherwise.
    private var slots: some View {
        ViewThatFits(in: .horizontal) {
            HStack(alignment: .center, spacing: 10) {
                slot(0)
                Image(systemName: "plus")
                    .font(.caption.weight(.bold)).foregroundStyle(.tertiary)
                    .accessibilityHidden(true)
                slot(1)
            }
            VStack(spacing: 8) {
                slot(0)
                slot(1)
            }
        }
    }

    @ViewBuilder private func slot(_ index: Int) -> some View {
        if index < state.sources.count {
            let source = state.sources[index]
            FusionSourceCard(index: index + 1, source: source,
                             remove: { state.remove(source.id) },
                             replace: { state.pick(replacing: source.id) })
                .disabled(state.isBusy)
                .frame(minWidth: 190)
        } else {
            FusionEmptySlot(index: index + 1) { state.pick(replacing: state.replacingID) }
                .disabled(state.isBusy)
                .frame(minWidth: 190)
        }
    }
}
