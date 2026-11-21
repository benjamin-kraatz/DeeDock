import SwiftUI

/// New Smart Filter.
///
/// With phase B2's generator, a sentence ("everything for Oak & Ash") becomes a proposal with its
/// rules spelled out and a match count. Without one, and always below it, a short rule builder:
/// a name, an emoji, and up to four rules, all of which must match.
struct FlixSmartFilterSheet: View {
    let state: FlixPanelState
    @State private var sentence = ""
    @State private var name = ""
    @State private var emoji = "✨"
    @State private var rules: [FlixRuleDraft] = [FlixRuleDraft()]
    @FocusState private var focused: Bool

    var body: some View {
        FlixSheetTitle(title: Text(.flixNewSmartFilterTitle), intelligent: state.intelligence.canGenerateSmartFilters) {
            state.sheet = nil
        }
        if state.intelligence.canGenerateSmartFilters {
            generator
            Divider()
        }
        builder
    }

    // MARK: From a sentence

    @ViewBuilder private var generator: some View {
        TextField(text: $sentence) { Text(.flixSmartFilterDescribePlaceholder) }
            .textFieldStyle(.roundedBorder)
            .focused($focused)
            .onSubmit { generate(sentence) }
            .onAppear { focused = true }
        HStack(spacing: 6) {
            ForEach(state.intelligence.smartFilterExamples, id: \.self) { example in
                Button { sentence = example; generate(example) } label: { Text(verbatim: example) }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                    .clipShape(.capsule)
            }
        }
        switch state.intelligence.smartFilterDraft {
        case .idle: EmptyView()
        case .generating: FlixShimmer(reduceMotion: state.reduceMotion)
        case .failed:
            Text(.flixSmartFilterFailed).font(.system(size: 12)).foregroundStyle(.secondary)
        case .ready(let proposal):
            FlixSmartFilterProposalView(proposal: proposal,
                                        count: state.history.items.count { item in
                                            proposal.filter.matches(item, now: state.now) { topic, item in
                                                state.intelligence.semanticMatch(topic: topic, item: item)
                                            }
                                        },
                                        add: { state.addSmartFilter(proposal.filter) })
        }
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
                .frame(width: 44)
                .accessibilityLabel(Text(.flixSmartFilterEmoji))
            TextField(text: $name) { Text(.flixSmartFilterNamePlaceholder) }
                .textFieldStyle(.roundedBorder)
        }
        ForEach($rules) { $rule in
            FlixRuleRow(rule: $rule, remove: rules.count > 1 ? { rules.removeAll { $0.id == rule.id } } : nil)
        }
        HStack(spacing: 8) {
            if rules.count < 4 {
                Button { rules.append(FlixRuleDraft()) } label: { Label { Text(.flixSmartFilterAddRule) } icon: { Image(systemName: "plus") } }
                    .buttonStyle(.borderless)
            }
            Spacer(minLength: 0)
            let filter = draftFilter
            if let filter {
                Text(.flixSmartFilterMatchCount(state.history.items.count { filter.matches($0, now: state.now) }))
                    .font(.system(size: 11.5))
                    .foregroundStyle(.secondary)
            }
            Button { if let filter { state.addSmartFilter(filter) } } label: { Text(.flixSmartFilterAdd) }
                .buttonStyle(.borderedProminent)
                .disabled(filter == nil)
                .keyboardShortcut(.defaultAction)
        }
        .controlSize(.small)
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
        HStack(alignment: .top, spacing: 12) {
            Text(verbatim: proposal.filter.emoji).font(.system(size: 26))
            VStack(alignment: .leading, spacing: 2) {
                Text(verbatim: proposal.filter.name).fontWeight(.semibold)
                ForEach(proposal.ruleDescriptions, id: \.self) { rule in
                    Text((try? AttributedString(markdown: rule)) ?? AttributedString(rule))
                }
                Text(.flixSmartFilterProposalCount(count))
            }
            .font(.system(size: 11.5))
            .foregroundStyle(.secondary)
            Spacer(minLength: 0)
            Button(action: add) { Text(.flixSmartFilterAddToSidebar) }
                .buttonStyle(.borderedProminent)
                .controlSize(.small)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background(FlixStyle.pane, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
    }
}
