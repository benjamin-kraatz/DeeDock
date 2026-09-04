import AppKit
import SwiftUI

/// The editable draft a capsule must pass through before it is saved.
///
/// The draft is the only place the user can correct what the summarizer inferred, so each field is a
/// labelled card with its own placeholder rather than a dense stack of system controls.
struct SessionCapsuleDraftForm: View {
    @Binding var draft: SessionCapsuleDraft
    let save: () -> Void

    @FocusState private var focus: CapsuleDraftField?

    /// Beyond a handful of open threads a capsule stops being a checkpoint and becomes a to-do list.
    private static let taskLimit = 6

    var body: some View {
        VStack(spacing: 0) {
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    titleField
                    summarySection
                    taskSection
                    noteSection
                    SessionCapsuleWindowList(windows: draft.windows)
                }
                .padding(18)
            }
            Divider()
            footer
        }
    }

    // MARK: - Fields

    private var titleField: some View {
        SessionCapsuleFormSection(.capsulesTitle, symbol: "textformat") {
            TextField(text: $draft.title) { Text(.capsulesTitlePlaceholder) }
                .textFieldStyle(.plain)
                .font(.title3.weight(.semibold))
                .focused($focus, equals: .title)
                .padding(.horizontal, 12)
                .padding(.vertical, 10)
                .capsuleFormField(focused: focus == .title)
        }
    }

    private var summarySection: some View {
        SessionCapsuleFormSection(.capsulesSummary, symbol: "text.alignleft") {
            CapsuleTextEditor(text: $draft.summary, placeholder: .capsulesSummaryPlaceholder,
                              minimumHeight: 92, field: .summary, focus: $focus)
        }
    }

    private var noteSection: some View {
        SessionCapsuleFormSection(.capsulesNoteHeading, symbol: "bookmark", badge: .capsulesOptional) {
            CapsuleTextEditor(text: $draft.note, placeholder: .capsulesNotePlaceholder,
                              minimumHeight: 60, field: .note, focus: $focus)
        }
    }

    private var taskSection: some View {
        SessionCapsuleFormSection(.capsulesUnfinished, symbol: "checklist.unchecked") {
            Button(.capsulesAddTask, systemImage: "plus") { addTask() }
                .buttonStyle(.borderless)
                .controlSize(.small)
                .disabled(draft.unfinishedTasks.count >= Self.taskLimit)
        } content: {
            if draft.unfinishedTasks.isEmpty {
                Text(.capsulesUnfinishedHint)
                    .font(.caption).foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 12).padding(.vertical, 10)
                    .background(.quaternary.opacity(0.35), in: .rect(cornerRadius: 10))
                    .overlay {
                        RoundedRectangle(cornerRadius: 10)
                            .strokeBorder(style: StrokeStyle(lineWidth: 1, dash: [4, 4]))
                            .foregroundStyle(.quaternary)
                    }
            } else {
                VStack(spacing: 6) {
                    ForEach(Array(draft.unfinishedTasks.indices), id: \.self) { index in
                        taskRow(index)
                    }
                }
            }
        }
    }

    private func taskRow(_ index: Int) -> some View {
        HStack(spacing: 9) {
            Image(systemName: "circle")
                .font(.caption).foregroundStyle(.tertiary).accessibilityHidden(true)
            TextField(text: taskBinding(index)) { Text(.capsulesTaskPlaceholder) }
                .textFieldStyle(.plain)
                .focused($focus, equals: .task(index))
            Button { removeTask(index) } label: {
                Image(systemName: "xmark.circle.fill").foregroundStyle(.tertiary)
            }
            .buttonStyle(.borderless)
            .help(Text(.capsulesRemoveTask))
            .accessibilityLabel(Text(.capsulesRemoveTask))
        }
        .padding(.horizontal, 10).padding(.vertical, 8)
        .capsuleFormField(focused: focus == .task(index))
    }

    private var footer: some View {
        HStack(spacing: 10) {
            Image(systemName: "lock.shield").foregroundStyle(.secondary).accessibilityHidden(true)
            Text(.capsulesPrivacyNote).font(.caption).foregroundStyle(.secondary)
            Spacer(minLength: 12)
            Button(.capsulesSave) { save() }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
                .keyboardShortcut(.defaultAction)
                .disabled(!draft.canSave)
        }
        .padding(.horizontal, 16).padding(.vertical, 12)
    }

    // MARK: - Editing

    private func addTask() {
        guard draft.unfinishedTasks.count < Self.taskLimit else { return }
        draft.unfinishedTasks.append("")
        focus = .task(draft.unfinishedTasks.count - 1)
    }

    private func removeTask(_ index: Int) {
        guard draft.unfinishedTasks.indices.contains(index) else { return }
        // Focus indices shift with the array, so drop focus rather than leave it on another row.
        focus = nil
        _ = withAnimation(.easeInOut(duration: 0.15)) { draft.unfinishedTasks.remove(at: index) }
    }

    private func taskBinding(_ index: Int) -> Binding<String> {
        Binding(get: { draft.unfinishedTasks.indices.contains(index) ? draft.unfinishedTasks[index] : "" },
                set: { if draft.unfinishedTasks.indices.contains(index) { draft.unfinishedTasks[index] = $0 } })
    }
}

// MARK: - Building blocks

/// Keeps the focus ring, and each task row's delete affordance, aligned with the focused field.
private enum CapsuleDraftField: Hashable { case title, summary, note, task(Int) }

/// One labelled card in the capsule draft: caption header, optional badge and accessory, then content.
struct SessionCapsuleFormSection<Accessory: View, Content: View>: View {
    private let title: LocalizedStringResource
    private let symbol: String
    private let badge: LocalizedStringResource?
    private let accessory: Accessory
    private let content: Content

    init(_ title: LocalizedStringResource, symbol: String, badge: LocalizedStringResource? = nil,
         @ViewBuilder accessory: () -> Accessory, @ViewBuilder content: () -> Content) {
        self.title = title
        self.symbol = symbol
        self.badge = badge
        self.accessory = accessory()
        self.content = content()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 6) {
                Image(systemName: symbol).font(.caption2).foregroundStyle(.secondary)
                    .accessibilityHidden(true)
                Text(title).font(.caption.weight(.semibold)).foregroundStyle(.secondary)
                if let badge {
                    Text(badge)
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                        .padding(.horizontal, 6).padding(.vertical, 1)
                        .background(.quaternary.opacity(0.6), in: .capsule)
                }
                Spacer(minLength: 8)
                accessory
            }
            content
        }
    }
}

extension SessionCapsuleFormSection where Accessory == EmptyView {
    init(_ title: LocalizedStringResource, symbol: String, badge: LocalizedStringResource? = nil,
         @ViewBuilder content: () -> Content) {
        self.init(title, symbol: symbol, badge: badge, accessory: { EmptyView() }, content: content)
    }
}

/// Multi-line draft field. `TextEditor` has no placeholder, so an inert overlay supplies one.
private struct CapsuleTextEditor: View {
    @Binding var text: String
    let placeholder: LocalizedStringResource
    let minimumHeight: CGFloat
    let field: CapsuleDraftField
    var focus: FocusState<CapsuleDraftField?>.Binding

    var body: some View {
        TextEditor(text: $text)
            .font(.body)
            .scrollContentBackground(.hidden)
            .focused(focus, equals: field)
            .frame(minHeight: minimumHeight)
            .padding(.horizontal, 8).padding(.vertical, 7)
            .overlay(alignment: .topLeading) {
                if text.isEmpty {
                    Text(placeholder)
                        .foregroundStyle(.tertiary)
                        .padding(.horizontal, 13).padding(.vertical, 15)
                        .allowsHitTesting(false)
                }
            }
            .capsuleFormField(focused: focus.wrappedValue == field)
    }
}

/// The windows a capsule points back to, shown with each application's real icon.
struct SessionCapsuleWindowList: View {
    let windows: [SessionCapsuleWindowReference]

    var body: some View {
        SessionCapsuleFormSection(.capsulesIncludedWindows, symbol: "macwindow") {
            VStack(spacing: 0) {
                ForEach(Array(windows.enumerated()), id: \.element.id) { index, window in
                    if index > 0 { Divider().padding(.leading, 42) }
                    row(window)
                }
            }
            .background(.quaternary.opacity(0.35), in: .rect(cornerRadius: 10))
        }
    }

    private func row(_ window: SessionCapsuleWindowReference) -> some View {
        HStack(spacing: 10) {
            icon(for: window)
            VStack(alignment: .leading, spacing: 1) {
                Text(window.windowTitle ?? String(localized: .capsulesUntitledWindow))
                    .lineLimit(1)
                Text(window.applicationName).font(.caption).foregroundStyle(.secondary).lineLimit(1)
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 10).padding(.vertical, 8)
        .accessibilityElement(children: .combine)
    }

    @ViewBuilder private func icon(for window: SessionCapsuleWindowReference) -> some View {
        if let image = SessionCapsuleApplicationIcons.icon(for: window.bundleIdentifier) {
            Image(nsImage: image).resizable().frame(width: 22, height: 22)
                .accessibilityHidden(true)
        } else {
            Image(systemName: "macwindow").foregroundStyle(.secondary)
                .frame(width: 22, height: 22).accessibilityHidden(true)
        }
    }
}

extension View {
    /// Read-only counterpart of the draft field surface, for saved capsule detail cards.
    func capsuleReadingCard() -> some View {
        padding(.horizontal, 12).padding(.vertical, 10)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(.quaternary.opacity(0.35), in: .rect(cornerRadius: 10))
    }
}

private extension View {
    /// Shared draft field surface: a soft fill whose border picks up the accent colour while focused.
    func capsuleFormField(focused: Bool) -> some View {
        background(.quaternary.opacity(0.45), in: .rect(cornerRadius: 10))
            .overlay {
                RoundedRectangle(cornerRadius: 10)
                    .strokeBorder(focused ? AnyShapeStyle(Color.accentColor.opacity(0.75))
                                          : AnyShapeStyle(.quaternary),
                                  lineWidth: focused ? 1.5 : 1)
            }
            .animation(.easeOut(duration: 0.12), value: focused)
    }
}

#if DEBUG
#Preview("Capsule Draft") {
    @Previewable @State var draft = SessionCapsuleDraft(
        title: "Continue Claude Code",
        summary: "Selected work across Ghostty. Add the current state and next step before saving.",
        unfinishedTasks: ["Review the permission fallback"],
        windows: [.init(applicationName: "Ghostty", bundleIdentifier: "com.mitchellh.ghostty",
                        windowTitle: "Claude Code"),
                  .init(applicationName: "Xcode", bundleIdentifier: "com.apple.dt.Xcode",
                        windowTitle: "DeeDock")],
        note: "")
    SessionCapsuleDraftForm(draft: $draft, save: {}).frame(width: 560, height: 560)
}
#endif
