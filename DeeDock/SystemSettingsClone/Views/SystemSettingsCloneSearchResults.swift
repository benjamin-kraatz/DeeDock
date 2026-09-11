import SwiftUI

/// Ranked results with a prominent top hit and a keyboard selection that follows ↑/↓.
///
/// Hovering moves the selection too, so mouse and keyboard never disagree about
/// what Return will open.
struct SystemSettingsCloneSearchResults: View {
    let results: [SystemSettingsCloneSearchResult]
    @Binding var selectedIndex: Int
    let launchCounts: [String: Int]
    let open: (SystemSettingsClonePane) -> Void
    @Namespace private var selectionNamespace
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView {
                VStack(alignment: .leading, spacing: 4) {
                    ForEach(Array(results.enumerated()), id: \.element.id) { index, result in
                        if index == 1 {
                            Text(.systemSettingsCloneMoreResults)
                                .font(.system(size: 11, weight: .semibold))
                                .foregroundStyle(.secondary)
                                .textCase(.uppercase)
                                .padding(.leading, 12)
                                .padding(.top, 14)
                                .padding(.bottom, 2)
                                .accessibilityAddTraits(.isHeader)
                        }
                        SystemSettingsCloneResultRow(
                            result: result,
                            isTopHit: index == 0,
                            isSelected: index == selectedIndex,
                            launchCount: launchCounts[result.pane.id, default: 0],
                            selectionNamespace: selectionNamespace
                        ) {
                            open(result.pane)
                        }
                        .id(result.id)
                        .onHover { hovering in
                            if hovering { selectedIndex = index }
                        }
                    }
                }
                .frame(maxWidth: SystemSettingsCloneMetrics.contentMaxWidth - 120, alignment: .leading)
                .frame(maxWidth: .infinity)
                .padding(.horizontal, 28)
                .padding(.top, 8)
                .padding(.bottom, 28)
            }
            .scrollEdgeEffectStyle(.soft, for: .top)
            .animation(Animation.systemSettingsClone(reduceMotion: reduceMotion), value: results.map(\.id))
            .animation(reduceMotion ? nil : .spring(duration: 0.22, bounce: 0.12), value: selectedIndex)
            .onChange(of: selectedIndex) { _, index in
                guard results.indices.contains(index) else { return }
                withAnimation(Animation.systemSettingsClone(reduceMotion: reduceMotion)) {
                    proxy.scrollTo(results[index].id)
                }
            }
        }
    }
}

/// One result. The top hit gets a larger icon and its full description.
private struct SystemSettingsCloneResultRow: View {
    let result: SystemSettingsCloneSearchResult
    let isTopHit: Bool
    let isSelected: Bool
    let launchCount: Int
    let selectionNamespace: Namespace.ID
    let action: () -> Void

    private var shape: RoundedRectangle {
        RoundedRectangle(cornerRadius: isTopHit ? 18 : 12, style: .continuous)
    }

    var body: some View {
        Button(action: action) {
            HStack(spacing: isTopHit ? 16 : 12) {
                SystemSettingsCloneIconTile(
                    symbolName: result.pane.symbolName,
                    tint: result.pane.tint,
                    size: isTopHit ? 52 : 30
                )
                .symbolEffect(.bounce, value: launchCount)
                VStack(alignment: .leading, spacing: isTopHit ? 4 : 1) {
                    if isTopHit {
                        Text(.systemSettingsCloneTopHit)
                            .font(.system(size: 10.5, weight: .semibold))
                            .foregroundStyle(result.pane.tint.accent)
                            .textCase(.uppercase)
                    }
                    titleText
                        .font(.system(size: isTopHit ? 19 : 13.5, weight: isTopHit ? .semibold : .regular))
                        .lineLimit(1)
                    HStack(spacing: 5) {
                        Text(result.category.title)
                            .foregroundStyle(.secondary)
                        Text(verbatim: "·")
                            .foregroundStyle(.tertiary)
                        Text(result.pane.detail)
                            .foregroundStyle(.secondary)
                    }
                    .font(.system(size: isTopHit ? 12.5 : 11.5))
                    .lineLimit(1)
                }
                Spacer(minLength: 8)
                if isSelected {
                    HStack(spacing: 6) {
                        Text(.systemSettingsCloneKeyOpen)
                            .font(.system(size: 11.5, weight: .medium))
                            .foregroundStyle(.secondary)
                        SystemSettingsCloneKeyCap(label: "↩")
                    }
                    .transition(.opacity.combined(with: .offset(x: 6)))
                }
            }
            .padding(.horizontal, isTopHit ? 16 : 12)
            .padding(.vertical, isTopHit ? 14 : 8)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background {
                if isTopHit {
                    shape.fill(result.pane.tint.accent.opacity(0.08))
                }
            }
            .background {
                if isSelected {
                    shape
                        .fill(Color.accentColor.opacity(0.14))
                        .overlay { shape.strokeBorder(Color.accentColor.opacity(0.35), lineWidth: 1) }
                        .matchedGeometryEffect(id: "selection", in: selectionNamespace)
                }
            }
            .contentShape(shape)
        }
        .buttonStyle(SystemSettingsClonePressStyle())
        .accessibilityLabel(Text(result.pane.title))
        .accessibilityValue(Text(result.pane.detail))
        .accessibilityHint(Text(.systemSettingsCloneOpenHint))
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }

    /// Localized title with the characters that matched the query set in bold.
    private var titleText: Text {
        let title = String(localized: result.pane.title)
        var attributed = AttributedString(title)
        let characters = Array(title)
        var index = attributed.startIndex
        for offset in characters.indices {
            let next = attributed.characters.index(after: index)
            if result.highlightedOffsets.contains(offset) {
                attributed[index ..< next].inlinePresentationIntent = .stronglyEmphasized
                attributed[index ..< next].foregroundColor = .primary
            }
            index = next
        }
        return Text(attributed)
    }
}

#if DEBUG
#Preview("Results") {
    @Previewable @State var selection = 0
    SystemSettingsCloneSearchResults(
        results: SystemSettingsCloneSearchIndex().search("scr"),
        selectedIndex: $selection,
        launchCounts: [:],
        open: { _ in }
    )
    .frame(width: 700, height: 560)
}
#endif
