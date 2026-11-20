import SwiftUI

/// What a row is drawing, beyond its item.
struct FlixRowContext: Equatable {
    var match: FlixMatchKind?
    var isChild = false
    var versionCount = 0
    var versionGroup: String?
    var isExpanded = false
    var isNoise = false
    /// Set in the Fits card: the window's words this item answers.
    var fitPhrase: String?
    var memory: FlixDragReason?
}

/// One activity row: picture, name, event line, chips, a ✦ action, flag, and time.
///
/// Mouse handling lives in `FlixRowInteraction` behind the content, so the row's text never
/// steals presses; only its pills are buttons. Hover only highlights.
struct FlixRowView: View {
    let item: FlixItem
    let context: FlixRowContext
    let annotation: FlixItemAnnotation?
    let selected: Bool
    let dimmed: Bool
    let now: Date
    let policy: FlixReadPolicy
    var press: (Bool, Bool) -> Void = { _, _ in }
    var click: (Bool, Bool) -> Void = { _, _ in }
    var open: () -> Void = {}
    var beginDrag: (NSView, NSEvent) -> Void = { _, _ in }
    var menu: () -> NSMenu? = { nil }
    var toggleVersions: () -> Void = {}
    var moveSuggested: () -> Void = {}
    var renameSuggested: () -> Void = {}

    @State private var hovered = false

    private var foreground: Color { selected ? .white : .primary }
    private var showsAction: Bool { context.fitPhrase == nil && !context.isChild && context.match == nil }

    var body: some View {
        HStack(spacing: 10) {
            FlixThumbnailView(item: item, size: context.isChild ? 30 : FlixStyle.iconSize, policy: policy,
                              sensitive: annotation?.isSensitive == true)
                .allowsHitTesting(false)
            VStack(alignment: .leading, spacing: 1) {
                nameLine
                subtitle.allowsHitTesting(false)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            if showsAction { actionPill }
            if item.isFlagged {
                Image(systemName: "flag.fill")
                    .font(.system(size: 10))
                    .foregroundStyle(selected ? Color.white : .orange)
                    .accessibilityHidden(true)
            }
            Text(FlixRelativeTime.string(for: item.date, now: now))
                .font(.system(size: 11.5))
                .monospacedDigit()
                .foregroundStyle(selected ? Color.white.opacity(0.78) : Color.secondary.opacity(0.8))
                .frame(minWidth: 36, alignment: .trailing)
                .allowsHitTesting(false)
        }
        .padding(.leading, 8)
        .padding(.trailing, 10)
        .frame(height: context.isChild ? FlixStyle.childRowHeight : FlixStyle.rowHeight)
        .background {
            // Never hit-testable: presses go through to the interaction view behind it.
            RoundedRectangle(cornerRadius: FlixStyle.rowRadius, style: .continuous)
                .fill(selected ? Color.accentColor : hovered ? FlixStyle.hover : .clear)
                .allowsHitTesting(false)
        }
        .background {
            FlixRowInteraction(press: press, click: click, open: open, begin: beginDrag, menu: menu,
                               hover: { hovered = $0 })
        }
        .padding(.leading, context.isChild ? 22 : 0)
        .overlay(alignment: .topLeading) {
            if context.isChild { FlixVersionConnector().allowsHitTesting(false) }
        }
        .opacity(dimmed ? 0.4 : context.isNoise ? 0.55 : 1)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(Text(verbatim: item.name))
        .accessibilityValue(Text(verbatim: accessibilityValue))
        .accessibilityAddTraits(selected ? .isSelected : [])
        .accessibilityAction(named: Text(.flixMenuOpen)) { open() }
    }

    private var nameLine: some View {
        HStack(spacing: 6) {
            Text(verbatim: item.name)
                .font(.system(size: 13))
                .lineLimit(1)
                .truncationMode(.middle)
                .foregroundStyle(foreground)
                .allowsHitTesting(false)
            if context.versionCount > 1 {
                Button(action: toggleVersions) {
                    HStack(spacing: 2) {
                        Text(.flixVersionsCount(context.versionCount))
                        Image(systemName: context.isExpanded ? "chevron.up" : "chevron.down")
                            .font(.system(size: 7, weight: .bold))
                    }
                    .font(.system(size: 10.5, weight: .semibold))
                    .padding(.horizontal, 6)
                    .frame(height: 18)
                    .foregroundStyle(selected ? Color.white : .secondary)
                    .background(selected ? Color.white.opacity(0.22) : FlixStyle.chipHover,
                                in: RoundedRectangle(cornerRadius: 6, style: .continuous))
                }
                .buttonStyle(.plain)
                .fixedSize()
            }
            if context.isNoise {
                FlixFactChip(fact: FlixFact(text: String(localized: .flixNoiseChip)), selected: selected)
                    .allowsHitTesting(false)
            }
        }
    }

    @ViewBuilder private var subtitle: some View {
        HStack(spacing: 5) {
            if context.match == .meaning { FlixMeaningChip(selected: selected) }
            if let phrase = context.fitPhrase {
                FlixSparkle(size: 10)
                Text(.flixFitAsksFor(phrase))
                if let memory = context.memory {
                    Text(verbatim: "· ↺ " + memory.text).opacity(0.8)
                }
            } else if let caption = annotation?.caption {
                FlixSparkle(size: 10)
                Text(verbatim: caption)
                if annotation?.isSensitive == true { Text(.flixPreviewHidden) }
                Text(verbatim: "·")
                FlixEventLabel(item: item, selected: selected, short: true)
            } else {
                FlixEventLabel(item: item, selected: selected)
                if let folder = item.folderName { Text(verbatim: "· " + folder) }
            }
            ForEach(Array((annotation?.facts ?? []).prefix(2).enumerated()), id: \.offset) { _, fact in
                FlixFactChip(fact: fact, selected: selected)
            }
        }
        .font(.system(size: 11))
        .lineLimit(1)
        .foregroundStyle(selected ? Color.white.opacity(0.82) : .secondary)
    }

    @ViewBuilder private var actionPill: some View {
        if let folder = annotation?.folderSuggestion, item.activity == .downloaded {
            FlixActionPill(title: String(localized: .flixActionMoveTo(FileManager.default.displayName(atPath: folder))),
                           selected: selected, action: moveSuggested)
        } else if annotation?.renameSuggestion != nil, hovered || selected {
            FlixActionPill(title: String(localized: .flixActionRename), selected: selected, action: renameSuggested)
        }
    }

    private var accessibilityValue: String {
        var parts = [FlixEventLabel.text(for: item), FlixRelativeTime.string(for: item.date, now: now)]
        if let caption = annotation?.caption { parts.insert(caption, at: 0) }
        if item.isFlagged { parts.append(String(localized: .flixFilterFlagged)) }
        if context.match == .meaning { parts.append(String(localized: .flixByMeaning)) }
        return parts.joined(separator: ", ")
    }
}

/// A ✦ suggestion on a row: "✦ Move to Finance", "✦ Rename".
struct FlixActionPill: View {
    let title: String
    let selected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(verbatim: "✦ " + title)
                .font(.system(size: 11, weight: .semibold))
                .lineLimit(1)
                .padding(.horizontal, 8)
                .frame(height: 22)
                .foregroundStyle(selected ? Color.white : FlixStyle.aiViolet)
                .background(selected ? Color.white.opacity(0.22) : FlixStyle.aiSoft,
                            in: RoundedRectangle(cornerRadius: 7, style: .continuous))
                .overlay {
                    if !selected {
                        RoundedRectangle(cornerRadius: 7, style: .continuous).strokeBorder(FlixStyle.aiStroke, lineWidth: 0.5)
                    }
                }
        }
        .buttonStyle(.plain)
        .fixedSize()
    }
}

/// The elbow joining an older version to its newest one.
private struct FlixVersionConnector: View {
    var body: some View {
        Path { path in
            path.move(to: CGPoint(x: 10, y: -6))
            path.addLine(to: CGPoint(x: 10, y: 16))
            path.addQuadCurve(to: CGPoint(x: 18, y: 22), control: CGPoint(x: 10, y: 22))
        }
        .stroke(Color.primary.opacity(0.15), lineWidth: 1.5)
        .frame(width: 22, height: 22)
    }
}

#if DEBUG
#Preview("Rows") {
    let now = FlixPreviewData.now
    VStack(spacing: 2) {
        ForEach(FlixPreviewData.items.prefix(6)) { item in
            FlixRowView(item: item, context: FlixRowContext(versionCount: item.name.contains("contract") ? 3 : 0),
                        annotation: FlixPreviewData.annotations[item.id],
                        selected: item.id == FlixPreviewData.items[1].id, dimmed: false, now: now,
                        policy: FlixPreviewData.policy)
        }
        FlixRowView(item: FlixPreviewData.items[2], context: FlixRowContext(fitPhrase: "the signed contract",
                                                                             memory: FlixDragReason(text: "you've sent PDFs here before")),
                    annotation: nil, selected: false, dimmed: false, now: now, policy: FlixPreviewData.policy)
    }
    .padding()
    .frame(width: 520)
}
#endif
