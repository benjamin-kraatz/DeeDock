import SwiftUI

/// Native handoff controls remain available after the selected application comes forward.
struct WindowFileHandoffView: View {
    let state: WindowFileHandoffState

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(verbatim: state.appName).font(.headline)
            if let title = state.windowTitle {
                Text(verbatim: title).lineLimit(2)
            } else {
                Text(.fileRouteAppDestination).foregroundStyle(.secondary)
            }
            Text(.fileRouteHandoffHelp).font(.callout)
            if let preview = state.preview {
                DockFilePreview(item: preview) { state.preview = nil }
                    .frame(maxHeight: .infinity)
            } else {
                ScrollView {
                    VStack(alignment: .leading, spacing: 6) {
                        ForEach(state.documents.urls, id: \.self) { url in
                            HStack {
                                Text(verbatim: url.lastPathComponent).lineLimit(1)
                                Spacer()
                                Button(.fileRoutePreview, systemImage: "eye") {
                                    state.preview = DockFilePreviewItem(url: url, leases: [state.documents])
                                }
                                .labelStyle(.iconOnly)
                                .disabled(!state.valid || state.busy)
                            }
                        }
                    }
                }
                .frame(maxHeight: .infinity)
            }
            Label { Text(.fileRouteDragFiles) } icon: { Image(systemName: "doc.on.doc") }
                .frame(maxWidth: .infinity, minHeight: 38)
                .background(.quaternary, in: .rect(cornerRadius: 8))
                .overlay {
                    ShelfItemDragSourceView(id: UUID(), enabled: state.valid && !state.busy,
                        press: { _, _ in }, click: {}, cancelClick: {}, open: {},
                        begin: { view, event in
                            WindowFileDragSession.begin(state.documents, from: view, event: event)
                        })
                }
                .accessibilityHint(Text(.fileRouteDragHelp))
            HStack {
                Button(state.windowTitle == nil ? .fileRouteActivateApp : .fileRouteActivateWindow) { state.activate?() }
                    .disabled(!state.activationAvailable)
                Button(.fileRouteCopy) { state.copy?() }.keyboardShortcut("c", modifiers: .command)
            }
            .disabled(!state.valid || state.busy)
            Button(.fileRouteOpenApp) { state.open?() }
                .disabled(!state.valid || state.busy || state.openRequested)
            Text(.fileRouteOpenHelp).font(.caption).foregroundStyle(.secondary)
            if state.busy { ProgressView().controlSize(.small) }
            Text(state.status).font(.callout).textSelection(.enabled)
            if !state.failures.isEmpty {
                ScrollView { Text(verbatim: state.failures.joined(separator: "\n")).textSelection(.enabled) }
                    .frame(maxHeight: 90)
            }
            HStack {
                Spacer()
                Button(.fileRouteClose) { state.close?() }.keyboardShortcut(.cancelAction)
            }
        }
        .padding(16)
        .background(Color(nsColor: .windowBackgroundColor))
    }
}

#if DEBUG
#Preview("File handoff · exact destination") {
    let documents = DocumentResourceAccess([URL(fileURLWithPath: "/Preview/Project notes.txt")],
                                          startAccess: { _ in false }, stopAccess: { _ in })
    let state = WindowFileHandoffState(documents: documents, appName: "Preview App",
                                      windowTitle: "A long destination window title for layout inspection")
    state.busy = false
    state.valid = true
    state.status = .fileRouteReady
    return WindowFileHandoffView(state: state).frame(width: 500, height: 620)
}

#Preview("File handoff · unavailable source") {
    let documents = DocumentResourceAccess([URL(fileURLWithPath: "/Preview/Unavailable.txt")],
                                          startAccess: { _ in false }, stopAccess: { _ in })
    let state = WindowFileHandoffState(documents: documents, appName: "Preview App", windowTitle: nil)
    state.busy = false
    state.activationAvailable = false
    state.status = .fileRouteInvalid
    return WindowFileHandoffView(state: state).frame(width: 440, height: 580)
}
#endif
