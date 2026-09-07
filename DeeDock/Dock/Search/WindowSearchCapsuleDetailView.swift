import SwiftUI

/// A saved capsule opened from search results.
///
/// Capsules are historical checkpoints, so the header states when the checkpoint was taken before
/// any of its text, and deletion stays a deliberate, clearly destructive action at the end.
struct WindowSearchCapsuleDetailView: View {
    let capsule: SessionCapsule
    let onBack: () -> Void
    let onDelete: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 8) {
                Button { onBack() } label: {
                    Label { Text(.windowSearchBack) } icon: { Image(systemName: "chevron.left") }
                }
                .buttonStyle(.borderless)
                .keyboardShortcut("[", modifiers: .command)
                Spacer()
                Text(capsule.createdAt, format: .dateTime.year().month().day().hour().minute())
                    .font(.caption).foregroundStyle(.secondary)
            }
            .padding(.horizontal, WindowSearchStyle.contentPadding)
            .padding(.vertical, 10)
            Divider()
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(verbatim: capsule.title).font(.title2.weight(.semibold))
                        Label { Text(.windowSearchCapsuleEvidence) } icon: { Image(systemName: "archivebox") }
                            .font(.caption).foregroundStyle(.secondary)
                    }
                    section(.windowSearchCapsuleSummary, symbol: "text.alignleft") {
                        Text(verbatim: capsule.summary)
                    }
                    if !capsule.note.isEmpty {
                        section(.windowSearchCapsuleNote, symbol: "note.text") {
                            Text(verbatim: capsule.note)
                        }
                    }
                    if !capsule.unfinishedTasks.isEmpty {
                        section(.windowSearchCapsuleTasks, symbol: "checklist") {
                            VStack(alignment: .leading, spacing: 6) {
                                ForEach(Array(capsule.unfinishedTasks.enumerated()), id: \.offset) { _, task in
                                    Label { Text(verbatim: task) } icon: { Image(systemName: "circle") }
                                        .labelStyle(.titleAndIcon)
                                }
                            }
                        }
                    }
                    if !capsule.windows.isEmpty {
                        section(.windowSearchCapsuleWindows, symbol: "macwindow") {
                            VStack(alignment: .leading, spacing: 6) {
                                ForEach(capsule.windows) { window in
                                    VStack(alignment: .leading, spacing: 1) {
                                        Text(verbatim: window.windowTitle ?? window.applicationName).lineLimit(1)
                                        Text(verbatim: window.applicationName)
                                            .font(.caption).foregroundStyle(.secondary)
                                    }
                                    .frame(maxWidth: .infinity, alignment: .leading)
                                    .padding(8)
                                    .background(.quaternary.opacity(0.25), in: .rect(cornerRadius: 8))
                                }
                            }
                        }
                    }
                    Button(role: .destructive) { onDelete() } label: {
                        Label { Text(.windowSearchDeleteCapsule) } icon: { Image(systemName: "trash") }
                    }
                    .padding(.top, 4)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(WindowSearchStyle.contentPadding)
            }
        }
    }

    private func section<Content: View>(_ title: LocalizedStringResource, symbol: String,
                                        @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Label { Text(title) } icon: { Image(systemName: symbol) }
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
                .textCase(.uppercase)
            content()
                .font(.callout)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}

#Preview("Capsule") {
    WindowSearchCapsuleDetailView(capsule: SessionCapsule(title: "Invoice review",
        summary: "Checked September invoices before the handover.",
        unfinishedTasks: ["Send invoice 1042", "Ask about the missing receipt"],
        windows: [SessionCapsuleWindowReference(applicationName: "Preview",
            bundleIdentifier: "com.apple.Preview", windowTitle: "Invoice 1042.pdf")],
        note: "Totals matched the statement."), onBack: {}, onDelete: {})
        .frame(width: 640, height: 560)
}
