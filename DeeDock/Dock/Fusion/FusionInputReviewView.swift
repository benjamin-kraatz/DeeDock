import SwiftUI

/// Step two: exactly what will be sent to the on-device model, and what to do with it.
struct FusionInputReviewView: View {
    @Bindable var state: FusionState

    var body: some View {
        VStack(alignment: .leading, spacing: FusionMetrics.section) {
            FusionSection(.fusionReviewInput, symbol: "text.viewfinder") {
                VStack(spacing: 10) {
                    ForEach(Array(state.sources.enumerated()), id: \.element.id) { index, source in
                        FusionInputCard(index: index + 1, source: source) {
                            state.editSource(source.id, text: $0)
                        }
                    }
                }
            }
            FusionNotice(.fusionReviewHelp)
            FusionSection(.fusionOptionsTitle, symbol: "wand.and.sparkles") {
                VStack(alignment: .leading, spacing: 10) {
                    operationPicker
                    instructionField
                    Toggle(.fusionReviewed, isOn: $state.reviewed)
                        .font(.callout)
                        .padding(.horizontal, 11).padding(.vertical, 9)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .fusionCard()
                }
            }
        }
        .disabled(state.isBusy)
    }

    /// Segmented while the labels fit, a menu once a translation makes them too wide.
    private var operationPicker: some View {
        ViewThatFits(in: .horizontal) {
            picker.pickerStyle(.segmented).labelsHidden()
            picker.pickerStyle(.menu)
        }
    }

    private var picker: some View {
        Picker(.fusionOperation, selection: $state.operation) {
            ForEach(FusionOperation.allCases) { operation in
                Text(operation.label).tag(operation)
                    // Compare and differences need text from both sources; a checklist needs one.
                    .disabled(operation != .checklist && !state.hasTextInBoth)
            }
        }
    }

    private var instructionField: some View {
        VStack(alignment: .leading, spacing: 6) {
            TextField(.fusionInstruction, text: $state.instruction, axis: .vertical)
                .textFieldStyle(.plain)
                .lineLimit(2...4)
                .accessibilityLabel(Text(.fusionInstructionLabel))
                .onChange(of: state.instruction) { state.instruction = String(state.instruction.prefix(500)) }
                .padding(.horizontal, 11).padding(.vertical, 9)
                .fusionCard(emphasized: true)
            if !state.instruction.isEmpty {
                Text(.fusionInstructionCount(count: state.instruction.count))
                    .font(.caption2).foregroundStyle(.tertiary)
                    .frame(maxWidth: .infinity, alignment: .trailing)
            }
        }
    }
}

/// One captured source, opened for correction: its provenance on top, its text below, in one card.
private struct FusionInputCard: View {
    let index: Int
    let source: FusionSource
    let edit: (String) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .top, spacing: 9) {
                FusionAppIcon(bundleIdentifier: source.candidate.bundleIdentifier, size: 22)
                VStack(alignment: .leading, spacing: 1) {
                    Text(verbatim: source.candidate.applicationName)
                        .font(.subheadline.weight(.semibold)).lineLimit(1)
                    Text(verbatim: source.title)
                        .font(.caption).foregroundStyle(.secondary).lineLimit(1)
                }
                Spacer(minLength: 8)
                FusionCaptureBadge(state: source.captureState, edited: source.edited)
            }
            TextEditor(text: Binding(get: { source.text }, set: edit))
                .font(.callout)
                .scrollContentBackground(.hidden)
                .padding(.horizontal, 7).padding(.vertical, 6)
                .frame(height: 132)
                .background(.background.opacity(0.35), in: .rect(cornerRadius: 7))
                .overlay {
                    RoundedRectangle(cornerRadius: 7).strokeBorder(.quaternary, lineWidth: 1)
                }
                .accessibilityLabel(Text(.fusionInputFor(title: source.title)))
            Text(.fusionCharacterCount(count: source.text.count))
                .font(.caption2).foregroundStyle(.tertiary)
                .frame(maxWidth: .infinity, alignment: .trailing)
        }
        .padding(11)
        .fusionCard()
        .accessibilityElement(children: .contain)
        .accessibilityLabel(Text(.fusionSlotLabel(number: index)))
    }
}
