import SwiftUI

struct DockModePickerView: View {
    let state: DockModePickerState
    var previewReduceTransparency: Bool? = nil
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(.dockModesPickerTitle)
                .font(.headline)
                .padding(.horizontal, 14)
                .padding(.top, 12)
            ScrollView {
                LazyVStack(spacing: 3) {
                    ForEach(state.modes) { mode in
                        Button { state.choose?(mode.id) } label: {
                            HStack(spacing: 9) {
                                Image(systemName: mode.id == state.activeModeID ? "checkmark.circle.fill" : "circle")
                                    .foregroundStyle(mode.id == state.activeModeID ? AnyShapeStyle(.tint) : AnyShapeStyle(.tertiary))
                                    .accessibilityHidden(true)
                                Text(verbatim: mode.name)
                                    .lineLimit(1)
                                Spacer(minLength: 8)
                            }
                            .padding(.horizontal, 10)
                            .frame(height: 36)
                            .contentShape(.rect)
                            .background(mode.id == state.selectedID ? Color.accentColor.opacity(0.18) : .clear,
                                        in: .rect(cornerRadius: 7))
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel(Text(verbatim: mode.name))
                        .accessibilityValue(mode.id == state.activeModeID ? Text(.dockModesCurrent) : Text(""))
                    }
                }
                .padding(.horizontal, 8)
                .padding(.bottom, 8)
            }
        }
        .background((previewReduceTransparency ?? reduceTransparency) ? AnyShapeStyle(Color(nsColor: .windowBackgroundColor)) : AnyShapeStyle(.regularMaterial),
                    in: .rect(cornerRadius: 14))
        .overlay(.separator.opacity(0.7), in: .rect(cornerRadius: 14).stroke(lineWidth: 0.5))
        .padding(4)
    }
}

#if DEBUG
#Preview("Dock mode picker") {
    let first = DockMode(name: "Work")
    DockModePickerView(state: DockModePickerState(
        modes: [first, DockMode(name: "Writing"), DockMode(name: "Presentation")], activeModeID: first.id
    )).frame(width: 320, height: 190)
}
#Preview("Dock mode picker — long name and reduced transparency") {
    let first = DockMode(name: "Default")
    DockModePickerView(state: DockModePickerState(
        modes: [first, DockMode(name: "A presentation workspace with a long localized name")], activeModeID: first.id
    ), previewReduceTransparency: true)
    .frame(width: 320, height: 150)
}
#endif
