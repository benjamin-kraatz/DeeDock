import SwiftUI
import UniformTypeIdentifiers

/// Manual notes stay editable independently of generated interpretation and capture availability.
struct SessionBreadcrumbEditor: View {
    @Binding var draft: SessionCapsuleDraft
    let canCapture: Bool
    let capture: () -> Void
    let save: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            ScrollView {
                VStack(alignment: .leading, spacing: CapsuleMetrics.section) {
                    TextField(.capsulesTitle, text: bounded($draft.title, limit: 200))
                        .font(.title3.weight(.semibold))
                    SessionCapsuleFormSection(.breadcrumbYourNote, symbol: "bookmark") {
                        TextField(.breadcrumbNotePrompt, text: bounded($draft.note, limit: 8_000), axis: .vertical)
                            .lineLimit(3...8).textFieldStyle(.roundedBorder)
                    }
                    SessionCapsuleFormSection(.breadcrumbNextStep, symbol: "arrow.forward.circle") {
                        TextField(.breadcrumbNextStepPrompt, text: nextStep, axis: .vertical)
                            .lineLimit(2...5).textFieldStyle(.roundedBorder)
                    }
                    if let generatedAt = draft.breadcrumb?.generatedAt {
                        SessionCapsuleFormSection(.breadcrumbInterpretation, symbol: "sparkles") {
                            Text(generatedAt, format: .dateTime.year().month().day().hour().minute()).font(.caption)
                            Text(.breadcrumbReviewInterpretation).font(.caption).foregroundStyle(.secondary)
                            TextField(.capsulesSummary, text: bounded($draft.summary, limit: 8_000), axis: .vertical)
                                .lineLimit(3...8).textFieldStyle(.roundedBorder)
                            ForEach(draft.unfinishedTasks.indices, id: \.self) { index in
                                TextField(.breadcrumbSuggestedStep, text: taskBinding(index), axis: .vertical)
                                    .textFieldStyle(.roundedBorder)
                            }
                            Button(.breadcrumbRemoveInterpretation) {
                                draft.summary = ""
                                draft.unfinishedTasks = []
                                draft.breadcrumb?.generatedAt = nil
                            }
                        }
                    }
                    Text(.breadcrumbCaptureDisclosure).font(.caption).foregroundStyle(.secondary)
                    if canCapture {
                        Button(.breadcrumbCaptureDraft, systemImage: "sparkles", action: capture)
                    }
                    ForEach($draft.windows) { $reference in
                        SessionBreadcrumbSourceEditor(reference: $reference) {
                            draft.windows.removeAll { $0.id == reference.id }
                        }
                    }
                    Button(.breadcrumbAddSource, systemImage: "link.badge.plus") {
                        draft.windows.append(SessionCapsuleWindowReference(
                            applicationName: String(localized: .breadcrumbLinkedSource),
                            bundleIdentifier: nil, windowTitle: nil))
                    }
                    .disabled(draft.windows.count >= SessionCapsuleDocument.maximumWindowsPerCapsule)
                    Text(.breadcrumbRestoreLimits).font(.caption).foregroundStyle(.secondary)
                }
                .padding(CapsuleMetrics.page)
            }
            HStack {
                Text(.breadcrumbSaveHint).font(.caption).foregroundStyle(.secondary)
                Spacer()
                Button(.capsulesSave, action: save)
                    .buttonStyle(.borderedProminent)
                    .keyboardShortcut(.defaultAction)
                    .disabled(!draft.canSave)
            }
            .capsuleFooterBar()
        }
    }

    private var nextStep: Binding<String> {
        Binding(get: { draft.breadcrumb?.nextStep ?? "" },
                set: { draft.breadcrumb?.nextStep = String($0.prefix(2_000)) })
    }

    private func taskBinding(_ index: Int) -> Binding<String> {
        Binding(get: { draft.unfinishedTasks.indices.contains(index) ? draft.unfinishedTasks[index] : "" },
                set: { if draft.unfinishedTasks.indices.contains(index) {
                    draft.unfinishedTasks[index] = String($0.prefix(2_000))
                } })
    }

    private func bounded(_ binding: Binding<String>, limit: Int) -> Binding<String> {
        Binding(get: { binding.wrappedValue }, set: { binding.wrappedValue = String($0.prefix(limit)) })
    }
}

/// Links come from the user; document access comes from an explicit native file selection.
private struct SessionBreadcrumbSourceEditor: View {
    @Binding var reference: SessionCapsuleWindowReference
    let remove: () -> Void
    @State private var choosingDocument = false
    @State private var documentError: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(verbatim: reference.windowTitle ?? reference.applicationName).font(.headline)
                Spacer()
                Button(.breadcrumbRemoveSource, role: .destructive, action: remove)
            }
            Text(verbatim: reference.applicationName).font(.caption).foregroundStyle(.secondary)
            TextField(.breadcrumbLinkPrompt, text: Binding(
                get: { reference.link ?? "" },
                set: { reference.link = String($0.trimmingCharacters(in: .whitespacesAndNewlines).prefix(2_048)) }))
                .textFieldStyle(.roundedBorder)
            if reference.link?.isEmpty == false && reference.reopeningURL == nil {
                Text(.breadcrumbInvalidLink).font(.caption).foregroundStyle(.red)
            }
            HStack {
                Button(.breadcrumbChooseDocument) { choosingDocument = true }
                if let name = reference.documentName {
                    Text(verbatim: name).lineLimit(1)
                    Button(.breadcrumbRemoveDocument) {
                        reference.documentBookmark = nil
                        reference.documentName = nil
                    }
                }
            }
            if let documentError { Text(verbatim: documentError).font(.caption).foregroundStyle(.red) }
            if let preview = reference.textPreview {
                Text(.breadcrumbHistoricalPreview).font(.caption.weight(.semibold))
                if let time = reference.capturedAt {
                    Text(time, format: .dateTime.year().month().day().hour().minute().second()).font(.caption)
                }
                Text(verbatim: preview).font(.callout).textSelection(.enabled)
                Button(.breadcrumbRemovePreview) { reference.textPreview = nil }
            }
        }
        .capsuleReadingCard()
        .fileImporter(isPresented: $choosingDocument, allowedContentTypes: [.data], allowsMultipleSelection: false) { result in
            do {
                guard let url = try result.get().first else { return }
                let scoped = url.startAccessingSecurityScopedResource()
                defer { if scoped { url.stopAccessingSecurityScopedResource() } }
                let data = try url.bookmarkData(options: [.withSecurityScope, .securityScopeAllowOnlyReadAccess],
                                                includingResourceValuesForKeys: nil, relativeTo: nil)
                guard data.count <= 65_536 else { throw CocoaError(.fileReadTooLarge) }
                reference.documentBookmark = data
                reference.documentName = url.lastPathComponent
                documentError = nil
            } catch {
                documentError = String(localized: .breadcrumbDocumentUnavailable)
            }
        }
    }
}

#if DEBUG
#Preview("Manual breadcrumb") {
    @Previewable @State var draft = SessionCapsuleDraft(title: "Window matching", summary: "", unfinishedTasks: [],
        windows: [], note: "Checked duplicate window titles.",
        breadcrumb: SessionCapsuleBreadcrumb(nextStep: "Review the unavailable-window copy."))
    SessionBreadcrumbEditor(draft: $draft, canCapture: false, capture: {}, save: {})
        .frame(width: 560, height: 500)
}
#endif
