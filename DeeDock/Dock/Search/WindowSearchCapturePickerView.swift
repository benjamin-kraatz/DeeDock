import SwiftUI

/// The explicit consent step before any screenshot exists.
///
/// Only window metadata is shown here. Nothing is captured until the user confirms the selection,
/// and the four-window ceiling is visible rather than only enforced.
struct WindowSearchCapturePickerView: View {
    @Bindable var state: WindowSearchState

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            VStack(alignment: .leading, spacing: 6) {
                Text(.windowSearchCaptureTitle).font(.headline)
                Text(.windowSearchCaptureHelp)
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(.horizontal, WindowSearchStyle.contentPadding)
            .padding(.vertical, 12)
            Divider()
            ScrollView {
                LazyVStack(spacing: 4) {
                    ForEach(state.candidates) { candidate in
                        row(candidate)
                    }
                }
                .padding(.horizontal, WindowSearchStyle.contentPadding)
                .padding(.vertical, 10)
            }
            Divider()
            HStack(spacing: 10) {
                Text(verbatim: "\(state.captureSelection.count)/\(WindowSearchMatcher.maximumCaptures)")
                    .font(.callout.monospacedDigit())
                    .foregroundStyle(.secondary)
                Spacer()
                Button(.windowSearchCancel) { state.cancelWork() }
                Button(.windowSearchCaptureSelected) { state.captureSelected() }
                    .keyboardShortcut(.defaultAction)
                    .disabled(state.captureSelection.isEmpty)
            }
            .controlSize(.large)
            .padding(.horizontal, WindowSearchStyle.contentPadding)
            .padding(.vertical, 12)
        }
    }

    private func row(_ candidate: WindowContextCandidate) -> some View {
        let selected = state.captureSelection.contains(candidate.id)
        let full = !selected && state.captureSelection.count >= WindowSearchMatcher.maximumCaptures
        return Button { state.toggleCapture(candidate) } label: {
            HStack(spacing: 10) {
                Image(systemName: selected ? "checkmark.circle.fill" : "circle")
                    .font(.title3)
                    .foregroundStyle(selected ? AnyShapeStyle(Color.accentColor) : AnyShapeStyle(.tertiary))
                if let icon = NSRunningApplication(processIdentifier: candidate.processIdentifier)?.icon {
                    Image(nsImage: icon).resizable().interpolation(.high).frame(width: 22, height: 22)
                }
                VStack(alignment: .leading, spacing: 1) {
                    Text(verbatim: candidate.title ?? candidate.applicationName).lineLimit(1)
                    Text(verbatim: candidate.applicationName)
                        .font(.caption).foregroundStyle(.secondary).lineLimit(1)
                }
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 6)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(selected ? AnyShapeStyle(Color.accentColor.opacity(0.12)) : AnyShapeStyle(.clear),
                        in: .rect(cornerRadius: WindowSearchStyle.rowCorner))
            .contentShape(.rect(cornerRadius: WindowSearchStyle.rowCorner))
        }
        .buttonStyle(.plain)
        .disabled(full)
        .opacity(full ? 0.45 : 1)
        .accessibilityAddTraits(selected ? [.isButton, .isSelected] : .isButton)
    }
}
