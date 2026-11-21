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
    /// Set in the Fits card when the item will go out converted: "as PDF · 1.2 MB" (phase B1).
    var conversion: String?
    /// A link row's relation to files: "Source of “Invoice.pdf”" (phase B1).
    var relation: String?
    /// The typed text of a plain name search, drawn bold where the name contains it.
    var highlight: String?
    /// The item arrived while the panel was open: an accent rim and wash that fade.
    var isFresh = false
}

/// What VoiceOver can do with a row besides opening it. Each is offered only when set.
struct FlixRowActions {
    var reveal: (() -> Void)?
    var toggleFlag: (() -> Void)?
    var remove: (() -> Void)?

    init() {}

    /// The panel's own commands, for one item.
    init(state: FlixPanelState, item: FlixItem) {
        if item.url != nil { reveal = { state.reveal([item]) } }
        toggleFlag = { state.toggleFlag([item]) }
        remove = { state.remove([item]) }
    }
}

/// One activity row: picture, name, event line, chips, a ✦ action, flag, and time.
///
/// Mouse handling lives in `FlixRowInteraction` behind the content, so the row's text never
/// steals presses; only its pills are buttons. Hover only highlights. A selected row is accent
/// with white text. When the item is renamed the name resolves out of a blur (``FlixNameMorph``);
/// with Reduce Motion it simply changes.
struct FlixRowView: View {
    let item: FlixItem
    let context: FlixRowContext
    let annotation: FlixItemAnnotation?
    let selected: Bool
    let dimmed: Bool
    let now: Date
    let policy: FlixReadPolicy
    var reduceMotion = false
    var press: (Bool, Bool) -> Void = { _, _ in }
    var click: (Bool, Bool) -> Void = { _, _ in }
    var open: () -> Void = {}
    var beginDrag: (NSView, NSEvent) -> Void = { _, _ in }
    var menu: () -> NSMenu? = { nil }
    var toggleVersions: () -> Void = {}
    var moveSuggested: () -> Void = {}
    var renameSuggested: () -> Void = {}
    var actions = FlixRowActions()

    @State private var hovered = false

    private var showsAction: Bool { context.fitPhrase == nil && !context.isChild && context.match == nil }

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: FlixStyle.rowRadius, style: .continuous)
        HStack(spacing: 10) {
            FlixThumbnailView(item: item, size: context.isChild ? 30 : FlixStyle.iconSize, policy: policy,
                              sensitive: annotation?.isSensitive == true)
                .allowsHitTesting(false)
            VStack(alignment: .leading, spacing: 1) {
                nameLine
                FlixRowSubtitle(item: item, context: context, annotation: annotation, selected: selected)
                    .allowsHitTesting(false)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            if showsAction {
                // The hover-only Rename pill fades; the row's own highlight stays instant.
                Group { actionPill }
                    .animation(reduceMotion ? nil : FlixMotion.hover, value: hovered || selected)
            }
            if item.isFlagged {
                Image(systemName: "flag.fill")
                    .font(.system(size: 10))
                    .foregroundStyle(selected ? Color.white : .orange)
                    .transition(FlixMotion.pop(reduceMotion: reduceMotion, scale: 0.5))
                    .accessibilityHidden(true)
            }
            Text(FlixRelativeTime.string(for: item.date, now: now))
                .font(.system(size: 11.5))
                .monospacedDigit()
                .foregroundStyle(selected ? Color.white.opacity(0.78) : FlixStyle.faint)
                .frame(minWidth: 36, alignment: .trailing)
                .fixedSize()
                .allowsHitTesting(false)
        }
        .padding(.leading, 8)
        .padding(.trailing, 10)
        .frame(height: context.isChild ? FlixStyle.childRowHeight : FlixStyle.rowHeight)
        .background {
            // Never hit-testable: presses go through to the interaction view behind it.
            shape.fill(selected ? Color.accentColor : hovered ? FlixStyle.hover : .clear)
                .allowsHitTesting(false)
        }
        .overlay {
            if context.isFresh { FlixFreshHighlight(shape: shape) }
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
        .animation(reduceMotion ? nil : FlixMotion.hover, value: dimmed)
        .animation(FlixMotion.resolved(FlixMotion.dialog, reduceMotion: reduceMotion), value: item.isFlagged)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(Text(verbatim: item.name))
        .accessibilityValue(Text(verbatim: accessibilityValue))
        .accessibilityAddTraits(selected ? .isSelected : [])
        .accessibilityAction(named: Text(.flixMenuOpen)) { open() }
        .accessibilityActions {
            if let reveal = actions.reveal { Button(action: reveal) { Text(.flixMenuShowInFinder) } }
            if let toggleFlag = actions.toggleFlag {
                Button(action: toggleFlag) { Text(item.isFlagged ? .flixMenuUnflag : .flixMenuFlag) }
            }
            if let remove = actions.remove { Button(action: remove) { Text(.flixMenuRemove) } }
        }
    }

    private var nameLine: some View {
        HStack(spacing: 6) {
            Text(FlixRowName.attributed(item.name, highlight: context.highlight))
                .font(.system(size: 13))
                .lineLimit(1)
                .truncationMode(.middle)
                .foregroundStyle(selected ? Color.white : Color.primary)
                .modifier(FlixNameMorph(name: item.name, reduceMotion: reduceMotion))
                .allowsHitTesting(false)
            if context.versionCount > 1 {
                FlixVersionsPill(count: context.versionCount, expanded: context.isExpanded, selected: selected,
                                 reduceMotion: reduceMotion, action: toggleVersions)
            }
            if context.isNoise {
                FlixFactChip(fact: FlixFact(text: String(localized: .flixNoiseChip)), selected: selected)
                    .allowsHitTesting(false)
            }
        }
    }

    @ViewBuilder private var actionPill: some View {
        if let folder = annotation?.folderSuggestion, item.activity == .downloaded {
            FlixActionPill(title: String(localized: .flixActionMoveTo(FileManager.default.displayName(atPath: folder))),
                           selected: selected, action: moveSuggested)
                .frame(maxWidth: 190)
        } else if annotation?.renameSuggestion != nil, hovered || selected {
            FlixActionPill(title: String(localized: .flixActionRename), selected: selected, action: renameSuggested)
                .transition(.opacity)
        }
    }

    private var accessibilityValue: String {
        var parts = [FlixEventLabel.text(for: item), FlixRelativeTime.string(for: item.date, now: now)]
        if let caption = annotation?.caption { parts.insert(caption, at: 0) }
        if let phrase = context.fitPhrase { parts.insert(String(localized: .flixFitAsksFor(phrase)), at: 0) }
        if let memory = context.memory { parts.append(memory.text) }
        if let relation = context.relation { parts.append(relation) }
        if let conversion = context.conversion { parts.append(conversion) }
        parts.append(contentsOf: (annotation?.facts ?? []).prefix(2).map(\.text))
        if annotation?.isSensitive == true {
            parts.append(annotation?.sensitiveReason ?? String(localized: .flixPreviewHidden))
        }
        if item.isFlagged { parts.append(String(localized: .flixFilterFlagged)) }
        if context.match == .meaning { parts.append(String(localized: .flixByMeaning)) }
        if context.isNoise { parts.append(String(localized: .flixNoiseChip)) }
        // The ✦ inside localized strings is decoration; VoiceOver would spell it out.
        return parts.joined(separator: ", ").replacingOccurrences(of: "✦ ", with: "")
    }
}

/// The row's name, with the searched text bold where the name contains it.
enum FlixRowName {
    static func attributed(_ name: String, highlight: String?) -> AttributedString {
        var result = AttributedString(name)
        guard let highlight, !highlight.isEmpty,
              let found = name.range(of: highlight, options: [.caseInsensitive, .diacriticInsensitive]),
              let lower = AttributedString.Index(found.lowerBound, within: result),
              let upper = AttributedString.Index(found.upperBound, within: result) else { return result }
        result[lower..<upper].font = .system(size: 13, weight: .bold)
        return result
    }
}

/// The rim and wash on a row that arrived while the panel was open: accent, fading over 1.6
/// seconds. Plain opacity, so it is the same with Reduce Motion.
private struct FlixFreshHighlight: View {
    let shape: RoundedRectangle
    @State private var faded = false

    var body: some View {
        shape.fill(FlixStyle.accentSoft)
            .overlay(shape.strokeBorder(Color.accentColor, lineWidth: 1.5))
            .opacity(faded ? 0 : 1)
            .allowsHitTesting(false)
            .accessibilityHidden(true)
            .onAppear { withAnimation(.easeOut(duration: 1.6)) { faded = true } }
    }
}

/// ✦ Rename's name change: the new name starts blurred and faint and resolves over 0.7 seconds.
/// Triggered only by the name changing on a row that is already on screen. Off with Reduce Motion.
private struct FlixNameMorph: ViewModifier {
    let name: String
    let reduceMotion: Bool

    private struct Pose {
        var blur: CGFloat = 0
        var opacity: Double = 1
    }

    func body(content: Content) -> some View {
        content.keyframeAnimator(initialValue: Pose(), trigger: name) { view, pose in
            view.blur(radius: reduceMotion ? 0 : pose.blur).opacity(reduceMotion ? 1 : pose.opacity)
        } keyframes: { _ in
            KeyframeTrack(\.blur) {
                MoveKeyframe(4)
                CubicKeyframe(0, duration: 0.7)
            }
            KeyframeTrack(\.opacity) {
                MoveKeyframe(0.2)
                CubicKeyframe(1, duration: 0.7)
            }
        }
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
                                                                             memory: FlixDragReason(text: "you've sent PDFs here before"),
                                                                             conversion: "as PDF · 1.2 MB"),
                    annotation: nil, selected: false, dimmed: false, now: now, policy: FlixPreviewData.policy)
    }
    .padding()
    .frame(width: 520)
}

#Preview("Rows: child, noise, search, fresh, long, link") {
    let now = FlixPreviewData.now
    VStack(spacing: 2) {
        FlixRowView(item: FlixPreviewData.items[2], context: FlixRowContext(versionCount: 3, versionGroup: "contract", isExpanded: true),
                    annotation: FlixPreviewData.annotations[FlixPreviewData.items[2].id], selected: true, dimmed: false,
                    now: now, policy: FlixPreviewData.policy)
        FlixRowView(item: FlixPreviewData.items[10], context: FlixRowContext(isChild: true),
                    annotation: FlixPreviewData.annotations[FlixPreviewData.items[10].id], selected: false, dimmed: false,
                    now: now, policy: FlixPreviewData.policy)
        FlixRowView(item: FlixPreviewData.items[12], context: FlixRowContext(isNoise: true), annotation: nil,
                    selected: false, dimmed: false, now: now, policy: FlixPreviewData.policy)
        FlixRowView(item: FlixPreviewData.items[3], context: FlixRowContext(match: .meaning), 
                    annotation: FlixPreviewData.annotations[FlixPreviewData.items[3].id], selected: false, dimmed: false,
                    now: now, policy: FlixPreviewData.policy)
        FlixRowView(item: FlixPreviewData.items[1], context: FlixRowContext(match: .name, highlight: "invoice", isFresh: true),
                    annotation: nil, selected: false, dimmed: false, now: now, policy: FlixPreviewData.policy)
        FlixRowView(item: FlixPreviewData.longItem, context: FlixRowContext(),
                    annotation: FlixItemAnnotation(folderSuggestion: FlixPreviewData.home + "/Documents/Kundenunterlagen"),
                    selected: false, dimmed: false, now: now, policy: FlixPreviewData.policy)
        FlixRowView(item: FlixPreviewData.link, context: FlixRowContext(relation: "Source of “Invoice-2026-11.pdf”"),
                    annotation: nil, selected: false, dimmed: true, now: now, policy: FlixPreviewData.policy)
    }
    .padding()
    .frame(width: 520)
    .environment(\.locale, Locale(identifier: "de"))
}
#endif
