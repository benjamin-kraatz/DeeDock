import SwiftUI

/// One rule being built by hand in New Smart Filter.
struct FlixRuleDraft: Identifiable, Equatable {
    enum Field: String, CaseIterable, Identifiable {
        case name, location, source, fileExtension, kind, activity, days, flagged
        var id: Self { self }

        var title: LocalizedStringResource {
            switch self {
            case .name: .flixRuleName
            case .location: .flixRuleLocation
            case .source: .flixRuleSource
            case .fileExtension: .flixRuleExtension
            case .kind: .flixRuleKind
            case .activity: .flixRuleActivity
            case .days: .flixRuleDays
            case .flagged: .flixRuleFlagged
            }
        }

        var takesText: Bool { [.name, .location, .source, .fileExtension].contains(self) }
    }

    let id = UUID()
    var field: Field = .name
    var text = ""
    var kind: FlixItemKind = .document
    var activity: FlixActivity = .downloaded
    var days = 7

    /// The rule, or nil while a text rule is still empty.
    var rule: FlixSmartFilterRule? {
        let value = text.trimmingCharacters(in: .whitespaces)
        switch field {
        case .name: return value.isEmpty ? nil : .nameContains(value)
        case .location: return value.isEmpty ? nil : .locationContains(value)
        case .source: return value.isEmpty ? nil : .sourceContains(value)
        case .fileExtension: return value.isEmpty ? nil : .fileExtension(value)
        case .kind: return .kind(kind)
        case .activity: return .activity(activity)
        case .days: return .withinDays(days)
        case .flagged: return .flagged
        }
    }
}

/// A picker for the field and the control for its value.
struct FlixRuleRow: View {
    @Binding var rule: FlixRuleDraft
    let remove: (() -> Void)?

    var body: some View {
        HStack(spacing: 8) {
            Picker(selection: $rule.field) {
                ForEach(FlixRuleDraft.Field.allCases) { Text($0.title).tag($0) }
            } label: { Text(.flixRuleField) }
            .labelsHidden()
            .fixedSize()
            value
            Spacer(minLength: 0)
            if let remove {
                Button(action: remove) { Image(systemName: "minus.circle.fill").symbolRenderingMode(.hierarchical) }
                    .buttonStyle(.borderless)
                    .help(Text(.flixSmartFilterRemoveRule))
                    .accessibilityLabel(Text(.flixSmartFilterRemoveRule))
            }
        }
        .controlSize(.small)
    }

    @ViewBuilder private var value: some View {
        switch rule.field {
        case .name, .location, .source, .fileExtension:
            TextField(text: $rule.text) { Text(.flixRuleTextPlaceholder) }
                .textFieldStyle(.roundedBorder)
        case .kind:
            Picker(selection: $rule.kind) {
                ForEach([FlixItemKind.document, .image, .screenshot, .folder, .app, .link], id: \.self) { kind in
                    Text(Self.title(kind)).tag(kind)
                }
            } label: { Text(.flixRuleKind) }
            .labelsHidden()
            .fixedSize()
        case .activity:
            Picker(selection: $rule.activity) {
                ForEach([FlixActivity.opened, .downloaded, .created, .saved], id: \.self) { activity in
                    Text(Self.title(activity)).tag(activity)
                }
            } label: { Text(.flixRuleActivity) }
            .labelsHidden()
            .fixedSize()
        case .days:
            Stepper(value: $rule.days, in: 1...90) { Text(.flixRuleDaysValue(rule.days)).monospacedDigit() }
        case .flagged:
            EmptyView()
        }
    }

    static func title(_ kind: FlixItemKind) -> LocalizedStringResource {
        switch kind {
        case .document: .flixKindDocuments
        case .image: .flixKindImages
        case .screenshot: .flixKindScreenshots
        case .folder: .flixKindFolders
        case .app: .flixKindApps
        case .link, .other: .flixKindLinks
        }
    }

    static func title(_ activity: FlixActivity) -> LocalizedStringResource {
        switch activity {
        case .opened: .flixFilterOpened
        case .downloaded: .flixFilterDownloaded
        case .created: .flixFilterNew
        case .saved, .link, .kept: .flixFilterSaved
        }
    }
}
