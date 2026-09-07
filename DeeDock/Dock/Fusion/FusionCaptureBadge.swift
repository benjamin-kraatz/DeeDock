import SwiftUI

/// What the tray actually holds for one source, as a quiet pill rather than a line of grey prose.
///
/// Only the symbol carries colour: a source that is fine should not shout, and a source that failed
/// should be findable without reading every card.
struct FusionCaptureBadge: View {
    let state: FusionCaptureState
    var edited = false

    var body: some View {
        HStack(spacing: 5) {
            Image(systemName: symbol)
                .font(.caption2.weight(.semibold)).foregroundStyle(tint)
                .accessibilityHidden(true)
            Text(state.label).font(.caption2).foregroundStyle(.secondary).lineLimit(1)
            if edited {
                Text(verbatim: "·").font(.caption2).foregroundStyle(.tertiary).accessibilityHidden(true)
                Image(systemName: "pencil")
                    .font(.caption2).foregroundStyle(.secondary)
                    .accessibilityLabel(Text(.fusionEditedInput))
            }
        }
        .padding(.horizontal, 7).padding(.vertical, 3)
        .background(.quaternary.opacity(0.5), in: .capsule)
        .accessibilityElement(children: .combine)
    }

    private var symbol: String {
        switch state {
        case .notCaptured: "circle.dashed"
        case .visibleText: "text.viewfinder"
        case .truncated: "scissors"
        case .unreadable: "eye.slash"
        case .unavailable: "exclamationmark.triangle.fill"
        }
    }

    private var tint: Color {
        switch state {
        case .notCaptured: .secondary
        case .visibleText: .green
        case .truncated, .unreadable: .yellow
        case .unavailable: .red
        }
    }
}

#if DEBUG
#Preview("Capture badges") {
    VStack(alignment: .leading, spacing: 8) {
        FusionCaptureBadge(state: .notCaptured)
        FusionCaptureBadge(state: .visibleText)
        FusionCaptureBadge(state: .truncated, edited: true)
        FusionCaptureBadge(state: .unreadable)
        FusionCaptureBadge(state: .unavailable)
    }
    .padding()
}
#endif
