import SwiftUI

struct FusionSelectionView: View {
    let state: FusionState

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            ForEach(state.sources) { source in
                FusionSourceCard(source: source, remove: { state.remove(source.id) },
                                 replace: { state.pick(replacing: source.id) })
                    .disabled(state.isBusy)
            }
            Text(.fusionSelectionHelp).font(.caption).foregroundStyle(.secondary)
            if state.sources.count < 2 || state.showingPicker {
                Button(.fusionChooseWindows) { state.pick(replacing: state.replacingID) }
                    .disabled(state.isBusy)
            }
            if state.showingPicker {
                VStack(alignment: .leading, spacing: 8) {
                    ForEach(state.candidates) { candidate in
                        Button { state.select(candidate) } label: {
                            VStack(alignment: .leading) {
                                Text(verbatim: candidate.applicationName).fontWeight(.medium)
                                Text(verbatim: candidate.title ?? String(localized: .applicationMenuUntitledWindow))
                                    .foregroundStyle(.secondary).lineLimit(2)
                            }.frame(maxWidth: .infinity, alignment: .leading)
                        }
                        .disabled(state.isBusy || state.sources.contains(where: { $0.id == candidate.id }))
                    }
                    Button(.fusionClosePicker) { state.closePicker() }
                }
            }
        }
    }
}

