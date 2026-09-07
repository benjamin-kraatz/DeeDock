import SwiftUI

/// One status line for the search window's outcomes: retention terms, cautions, and failures.
///
/// Failures and model cautions are tinted so a privacy-relevant message is not read as chrome.
struct WindowSearchNoticeView: View {
    let message: LocalizedStringResource

    private var kind: WindowSearchNoticeKind { WindowSearchNoticeKind(message) }

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Image(systemName: kind.symbol).foregroundStyle(kind.tint)
            Text(message)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .font(.caption)
        .foregroundStyle(.secondary)
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .background(kind == .info ? AnyShapeStyle(.quaternary.opacity(0.3)) : AnyShapeStyle(kind.tint.opacity(0.12)),
                    in: .rect(cornerRadius: 8))
        .accessibilityElement(children: .combine)
    }
}

/// Captured-context controls: when the capture happened, what each window yielded, and how to
/// extend or discard it. It appears only while ephemeral content exists.
struct WindowSearchCapturedBarView: View {
    @Bindable var state: WindowSearchState

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                Label { Text(.windowSearchCapturedContext) } icon: { Image(systemName: "text.viewfinder") }
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                if let date = state.capturedAt {
                    Text(date, format: .dateTime.hour().minute().second())
                        .font(.caption.monospacedDigit())
                        .foregroundStyle(.tertiary)
                        .accessibilityLabel(Text(.windowSearchCapturedAt))
                }
                Spacer(minLength: 0)
                Button { state.searchImages() } label: {
                    Label { Text(.windowSearchImages) } icon: { Image(systemName: "sparkles") }
                }
                .disabled(state.busy || state.snapshots.isEmpty || state.query.isEmpty
                    || WindowSearchMatcher.wantsYesterday(state.query))
                Button(role: .destructive) { state.clearCaptured() } label: {
                    Image(systemName: "trash")
                }
                .help(Text(.windowSearchClear))
                .accessibilityLabel(Text(.windowSearchClear))
                .disabled(state.snapshots.isEmpty && !state.busy)
            }
            .controlSize(.small)
            ScrollView(.horizontal) {
                HStack(spacing: 8) {
                    // Every chosen window appears, including one whose content could not be read.
                    ForEach(state.snapshots, id: \.candidate.id) { snapshot in
                        chip(snapshot)
                    }
                }
            }
            .scrollIndicators(.never)
        }
    }

    private func chip(_ snapshot: WindowContextSnapshot) -> some View {
        HStack(spacing: 8) {
            WindowSearchThumbnailView(thumbnail: snapshot.image,
                icon: NSRunningApplication(processIdentifier: snapshot.candidate.processIdentifier)?.icon)
                .frame(width: 52, height: 34)
            VStack(alignment: .leading, spacing: 1) {
                Text(verbatim: snapshot.candidate.title ?? snapshot.candidate.applicationName)
                    .font(.caption.weight(.medium)).lineLimit(1)
                Text(snapshot.image == nil ? .windowSearchContentUnavailable
                     : snapshot.recognizedText.isEmpty ? .windowSearchNoText : .windowSearchTextAvailable)
                    .font(.caption2).foregroundStyle(.secondary).lineLimit(1)
            }
        }
        .padding(6)
        .frame(maxWidth: 240)
        .background(.quaternary.opacity(0.3), in: .rect(cornerRadius: 8))
        .accessibilityElement(children: .combine)
    }
}
