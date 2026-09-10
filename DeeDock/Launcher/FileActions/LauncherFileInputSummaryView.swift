import SwiftUI

/// Count, names, and unavailable inputs for the current file-action batch.
struct LauncherFileInputSummaryView: View {
    let state: LauncherFileActionState

    var body: some View {
        if let context = state.context {
            VStack(alignment: .leading, spacing: 8) {
                HStack(alignment: .firstTextBaseline) {
                    Label {
                        Text(.launcherFileInputCount(context.inputs.count))
                    } icon: {
                        Image(systemName: "doc.on.doc")
                    }
                    .font(.headline)
                    Spacer()
                    Button {
                        state.chooseFiles()
                    } label: {
                        Text(.launcherFileReplace)
                    }
                    .disabled(state.isBusy)
                    Button {
                        state.clear()
                    } label: {
                        Text(.launcherFileClear)
                    }
                    .disabled(state.status.isPending)
                }
                Text(sourceDetail(context.source))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                if state.overflowed {
                    Text(.launcherFileInputLimit).font(.caption).foregroundStyle(.secondary)
                }
                ScrollView(.horizontal) {
                    HStack(spacing: 8) {
                        ForEach(context.inputs) { input in
                            LauncherFileInputChip(input: input) {
                                state.remove(input.id)
                            }
                            .disabled(state.status.isPending)
                        }
                    }
                }
                .scrollIndicators(.hidden)
                if !context.unavailableInputs.isEmpty {
                    Text(.launcherFileUnavailableSummary(context.unavailableInputs.count))
                        .font(.caption)
                        .foregroundStyle(.red)
                }
            }
            .padding(12)
            .background(.primary.opacity(0.045), in: .rect(cornerRadius: 16))
            .accessibilityElement(children: .contain)
            .accessibilityLabel(Text(.launcherFileInputCount(context.inputs.count)))
        }
    }

    private func sourceDetail(_ source: LauncherFileSource) -> LocalizedStringResource {
        switch source {
        case .shelf: .launcherFileSourceShelf
        case .drop: .launcherFileSourceDrop
        case .picker: .launcherFileSourcePicker
        }
    }
}

private struct LauncherFileInputChip: View {
    let input: LauncherFileInput
    let remove: () -> Void

    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: input.isDirectory ? "folder" : "doc")
            Text(verbatim: input.name).lineLimit(1)
            if !input.isAvailable {
                Image(systemName: "exclamationmark.triangle.fill")
                    .foregroundStyle(.yellow)
                    .accessibilityLabel(Text(.launcherFileInputMissing))
            }
            Button(action: remove) {
                Image(systemName: "xmark.circle.fill")
            }
            .buttonStyle(.plain)
            .accessibilityLabel(Text(.launcherFileRemoveInput))
        }
        .font(.caption)
        .padding(.horizontal, 8)
        .padding(.vertical, 6)
        .background(.primary.opacity(0.06), in: .capsule)
        .opacity(input.isAvailable ? 1 : 0.7)
        .accessibilityElement(children: .combine)
        .accessibilityValue(input.isAvailable ? Text(verbatim: input.name) : Text(.launcherFileInputMissing))
    }
}

#if DEBUG
#Preview("File input summary") {
    let state = LauncherFileActionState()
    state.adopt(.owned(
        DocumentResourceAccess(
            [URL(fileURLWithPath: "/Preview/Report.pdf"), URL(fileURLWithPath: "/Preview/Missing.txt")],
            startAccess: { _ in false }, stopAccess: { _ in }
        ),
        source: .shelf
    ))
    return LauncherFileInputSummaryView(state: state)
        .padding()
        .frame(width: 640)
}

#Preview("File input summary, German") {
    let state = LauncherFileActionState()
    state.adopt(.owned(
        DocumentResourceAccess([URL(fileURLWithPath: "/Preview/Notes.txt")],
                               startAccess: { _ in false }, stopAccess: { _ in }),
        source: .picker
    ))
    return LauncherFileInputSummaryView(state: state)
        .padding()
        .frame(width: 640)
        .environment(\.locale, Locale(identifier: "de"))
}
#endif
