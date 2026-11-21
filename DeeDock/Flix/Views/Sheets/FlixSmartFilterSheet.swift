import SwiftUI

/// New Smart Filter.
///
/// With phase B2's generator, a sentence ("everything for Oak & Ash") becomes a proposal with its
/// rules spelled out and a match count. Without one, and always below it, a short rule builder:
/// a name, an emoji, and up to four rules, all of which must match. The proposal settles in with
/// ``FlixMotion/dialog``; rules slide in and out. With Reduce Motion both crossfade.
struct FlixSmartFilterSheet: View {
    let state: FlixPanelState
    @State private var sentence = ""
    @State private var name = ""
    @State private var emoji = "✨"
    @State private var rules: [FlixRuleDraft] = [FlixRuleDraft()]
    @FocusState private var focused: Bool
    @FocusState private var nameFocused: Bool

    private var generates: Bool { state.intelligence.canGenerateSmartFilters }

    var body: some View {
        FlixSheetTitle(title: Text(.flixNewSmartFilterTitle), intelligent: generates) {
            state.sheet = nil
        }
        if generates {
            generator
            FlixHairline()
        }
        builder
    }

    // MARK: From a sentence

    @ViewBuilder private var generator: some View {
        FlixSheetField(text: $sentence, prompt: Text(.flixSmartFilterDescribePlaceholder), focus: $focused) {
            generate(sentence)
        }
        .onAppear { focused = true }
        // Examples wrap onto further lines.
        FlixFlow {
            ForEach(state.intelligence.smartFilterExamples, id: \.self) { example in
                Button { sentence = example; generate(example) } label: { Text(verbatim: example) }
                    .buttonStyle(FlixChipButtonStyle())
            }
        }
        Group {
            switch state.intelligence.smartFilterDraft {
            case .idle: EmptyView()
            case .generating:
                FlixShimmer(reduceMotion: state.reduceMotion, height: 56)
                    .padding(.horizontal, -6)
                    .accessibilityLabel(Text(.flixLoading))
                    .transition(.opacity)
            case .failed:
                FlixSheetNote(text: Text(.flixSmartFilterFailed))
                    .transition(.opacity)
            case .ready(let proposal):
                FlixSmartFilterProposalView(proposal: proposal,
                                            count: state.history.items.count { item in
                                                proposal.filter.matches(item, now: state.now) { topic, item in
                                                    state.intelligence.semanticMatch(topic: topic, item: item)
                                                }
                                            },
                                            add: {
                                                state.addSmartFilter(proposal.filter, origin: .sentence,
                                                                     generator: proposal.generatedByModel ? .appleIntelligence : .rules)
                                            })
                    .transition(state.reduceMotion ? .opacity : .scale(scale: 0.96).combined(with: .opacity))
            }
        }
        .animation(FlixMotion.resolved(FlixMotion.dialog, reduceMotion: state.reduceMotion),
                   value: state.intelligence.smartFilterDraft)
    }

    private func generate(_ text: String) {
        let trimmed = text.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return }
        state.intelligence.generateSmartFilter(from: trimmed, items: state.history.items)
    }

    // MARK: By hand

    @ViewBuilder private var builder: some View {
        HStack(spacing: 8) {
            TextField(text: $emoji) { Text(verbatim: "✨") }
                .textFieldStyle(.roundedBorder)
                .multilineTextAlignment(.center)
                .frame(width: 44)
                .accessibilityLabel(Text(.flixSmartFilterEmoji))
            TextField(text: $name) { Text(.flixSmartFilterNamePlaceholder) }
                .textFieldStyle(.roundedBorder)
                .focused($nameFocused)
                .onAppear { if !generates { nameFocused = true } }
        }
        .controlSize(.small)
        VStack(alignment: .leading, spacing: 6) {
            ForEach($rules) { $rule in
                FlixRuleRow(rule: $rule, remove: rules.count > 1 ? { rules.removeAll { $0.id == rule.id } } : nil)
                    .transition(FlixMotion.rise(reduceMotion: state.reduceMotion))
            }
        }
        .animation(FlixMotion.resolved(FlixMotion.row, reduceMotion: state.reduceMotion), value: rules.map(\.id))
        HStack(spacing: 8) {
            if rules.count < 4 {
                Button { rules.append(FlixRuleDraft()) } label: {
                    Label { Text(.flixSmartFilterAddRule) } icon: { Image(systemName: "plus") }
                }
                .buttonStyle(.borderless)
                .controlSize(.small)
            }
            Spacer(minLength: 0)
            let filter = draftFilter
            if let filter {
                let matches = state.history.items.count { filter.matches($0, now: state.now) }
                Text(.flixSmartFilterMatchCount(matches))
                    .font(.system(size: 11.5))
                    .monospacedDigit()
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .contentTransition(state.reduceMotion ? .identity : .numericText(value: Double(matches)))
                    .animation(state.reduceMotion ? nil : FlixMotion.row, value: matches)
            }
            Button { if let filter { state.addSmartFilter(filter, origin: .manual) } } label: { Text(.flixSmartFilterAdd) }
                .buttonStyle(FlixCardButtonStyle(primary: true))
                .disabled(filter == nil)
                .keyboardShortcut(.defaultAction)
        }
    }

    private var draftFilter: FlixSmartFilter? {
        let built = rules.compactMap(\.rule)
        let title = name.trimmingCharacters(in: .whitespaces)
        guard !built.isEmpty, !title.isEmpty else { return nil }
        let glyph = emoji.trimmingCharacters(in: .whitespaces)
        return FlixSmartFilter(name: title, emoji: glyph.isEmpty ? "✨" : String(glyph.prefix(2)), rules: built)
    }
}

/// A generated filter, its rules in words, and Add to Sidebar.
private struct FlixSmartFilterProposalView: View {
    let proposal: FlixSmartFilterProposal
    let count: Int
    let add: () -> Void

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: 10, style: .continuous)
        HStack(alignment: .top, spacing: 12) {
            Text(verbatim: proposal.filter.emoji).font(.system(size: 26)).accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 2) {
                Text(verbatim: proposal.filter.name)
                    .font(.system(size: 12.5, weight: .semibold))
                    .foregroundStyle(.primary)
                    .lineLimit(1)
                ForEach(proposal.ruleDescriptions, id: \.self) { rule in
                    Text((try? AttributedString(markdown: rule)) ?? AttributedString(rule))
                        .fixedSize(horizontal: false, vertical: true)
                }
                Text(.flixSmartFilterProposalCount(count))
                    .fixedSize(horizontal: false, vertical: true)
            }
            .font(.system(size: 11.5))
            .lineSpacing(2)
            .foregroundStyle(.secondary)
            .frame(maxWidth: .infinity, alignment: .leading)
            Button(action: add) { Text(.flixSmartFilterAddToSidebar) }
                .buttonStyle(FlixCardButtonStyle(primary: true))
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background(FlixStyle.pane, in: shape)
        .overlay(shape.strokeBorder(FlixStyle.line, lineWidth: 0.5))
        .accessibilityElement(children: .contain)
    }
}

#if DEBUG
#Preview("New Smart Filter, proposal") {
    FlixPanelView(state: FlixPreviewData.panelState(.smartFilterProposal)).frame(width: 760, height: 608)
}

#Preview("New Smart Filter, by hand") {
    let state = FlixPreviewData.panelState()
    state.sheet = .smartFilter
    return FlixPanelView(state: state).frame(width: 760, height: 608)
}
#endif
