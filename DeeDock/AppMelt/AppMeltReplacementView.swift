import SwiftUI

/// Side selection remains visible above the grouped window menu, so every choice has a clear target.
struct AppMeltReplacementButton: View {
    @Bindable var state: AppMeltWindowPickerState
    let pair: AppMeltPair

    var body: some View {
        Button { state.isPresented.toggle() } label: {
            Label(.meltReplacementTitle, systemImage: "arrow.triangle.2.circlepath")
                .labelStyle(.iconOnly).frame(width: 38, height: 32)
        }
        .buttonStyle(AppMeltToolbarButtonStyle(selected: state.isPresented))
        .help(Text(.meltReplacementTitle))
        .disabled(!pair.canChangeLayout)
        .popover(isPresented: $state.isPresented, arrowEdge: .bottom) {
            VStack(alignment: .leading, spacing: 14) {
                Text(.meltReplacementTitle).font(.headline)
                Picker(selection: $state.side) {
                    Text(.meltReplacementLeft(pair.orderedNames[0])).tag(0)
                    Text(.meltReplacementRight(pair.orderedNames[1])).tag(1)
                } label: { Text(.meltReplacementSide) }
                .pickerStyle(.segmented)
                Text(.meltReplacementHelp).font(.caption).foregroundStyle(.secondary)
                AppMeltWindowPickerContents(state: state, disabled: pair.busy)
            }
            .padding(16).frame(width: 360)

        }
    }
}
