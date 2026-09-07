import SwiftUI

struct FusionDraftView: View {
    @Bindable var state: FusionState
    let draft: FusionDraft

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(.fusionReviewResult).font(.headline)
            TextField(.fusionArtifactTitle, text: Binding(get: { state.draft?.title ?? "" }, set: {
                state.draft?.title = String($0.prefix(160))
            })).disabled(state.savedURL != nil)
            TextEditor(text: Binding(get: { state.draft?.body ?? "" }, set: {
                state.draft?.body = String($0.prefix(20_000))
            })).frame(minHeight: 230).accessibilityLabel(Text(.fusionArtifactBody)).disabled(state.savedURL != nil)
            Text(.fusionSources).font(.headline)
            ForEach(Array(draft.sources.enumerated()), id: \.element.id) { index, source in
                VStack(alignment: .leading) {
                    Text(verbatim: "\(index + 1). \(source.application) · \(source.title)")
                    Text(source.state.label).font(.caption)
                    if let date = source.capturedAt { Text(date, format: .dateTime).font(.caption) }
                    if source.edited { Text(.fusionEditedInput).font(.caption) }
                }.foregroundStyle(.secondary)
            }
            Text(.fusionGeneratedOn).font(.caption)
            Text(draft.generatedAt, format: .dateTime).font(.caption)
            if let url = state.savedURL {
                Text(.fusionSaved).foregroundStyle(.secondary)
                Button(.fusionOpenArtifact) { NSWorkspace.shared.open(url) }
            } else {
                Button(.fusionSave) { state.save() }
                    .buttonStyle(.borderedProminent).disabled(state.isBusy || state.draft?.isValid != true)
            }
        }
        .disabled(state.isBusy)
    }
}

