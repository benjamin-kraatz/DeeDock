import SwiftUI

struct FusionInputReviewView: View {
    @Bindable var state: FusionState

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(.fusionReviewInput).font(.headline)
            Text(.fusionReviewHelp).font(.caption).foregroundStyle(.secondary)
            ForEach(state.sources) { source in
                VStack(alignment: .leading) {
                    Text(verbatim: source.title).font(.subheadline.bold())
                    TextEditor(text: Binding(get: {
                        state.sources.first(where: { $0.id == source.id })?.text ?? ""
                    }, set: { state.editSource(source.id, text: $0) }))
                        .frame(height: 120)
                        .accessibilityLabel(Text(.fusionInputFor(title: source.title)))
                    if source.edited { Text(.fusionEditedInput).font(.caption).foregroundStyle(.secondary) }
                }
            }
            Picker(.fusionOperation, selection: $state.operation) {
                ForEach(FusionOperation.allCases) { operation in
                    Text(operation.label).tag(operation)
                        .disabled(operation != .checklist && !state.hasTextInBoth)
                }
            }
            TextField(.fusionInstruction, text: $state.instruction, axis: .vertical)
                .lineLimit(2...4)
                .onChange(of: state.instruction) { state.instruction = String(state.instruction.prefix(500)) }
            Toggle(.fusionReviewed, isOn: $state.reviewed)
            Button(.fusionGenerate) { state.generate() }
                .buttonStyle(.borderedProminent).disabled(!state.canGenerate)
        }.disabled(state.isBusy)
    }
}

