import SwiftUI

/// The Files tab: tab strip, sidebar, panes or search results, preview column, and status bar.
struct HubFilesView: View {
    let model: HubFilesModel

    init(model: HubFilesModel) {
        self.model = model
    }

    var body: some View {
        VStack(spacing: 0) {
            HubFilesTabStrip(model: model)
            HStack(spacing: 0) {
                HubFilesSidebar(model: model)
                Group {
                    if model.isSearching {
                        HubFilesSearchResults(model: model)
                            .transition(.opacity)
                    } else {
                        HubFilesPanes(model: model, tab: model.selectedTab)
                            .transition(.opacity)
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                if model.showsPreview {
                    HubFilesPreviewColumn(model: model)
                        .transition(.move(edge: .trailing).combined(with: .opacity))
                }
            }
            .frame(maxHeight: .infinity)
            .clipped()
            HubFilesStatusBar(model: model)
        }
        .animation(HubFilesMotion.layout, value: model.showsPreview)
        .animation(HubFilesMotion.animation(.easeOut(duration: 0.18)), value: model.isSearching)
        .background { HubFilesQuickLookAnchor(controller: model.quickLook) }
        .modifier(HubFilesErrorAlert(model: model))
        .onChange(of: model.transfers.lastFinished?.id) { model.transferDidFinish() }
    }
}

/// Hosts the responder the system Quick Look panel finds through the responder chain.
private struct HubFilesQuickLookAnchor: NSViewRepresentable {
    let controller: HubFilesQuickLook

    func makeNSView(context: Context) -> HubFilesQuickLookResponderView {
        let view = HubFilesQuickLookResponderView()
        view.controller = controller
        controller.responderView = view
        return view
    }

    func updateNSView(_ view: HubFilesQuickLookResponderView, context: Context) {
        view.controller = controller
        controller.responderView = view
    }

    static func dismantleNSView(_ view: HubFilesQuickLookResponderView, coordinator: ()) {
        view.controller?.close()
        view.controller = nil
    }
}

/// Shows a failed file operation and holds an anchored Hub open while the alert is up.
private struct HubFilesErrorAlert: ViewModifier {
    @Bindable var model: HubFilesModel
    @State private var holdingShell: HubShell?

    func body(content: Content) -> some View {
        content
            .alert(Text(.hubFilesAlertTitle), isPresented: isPresented) {
                Button(.hubFilesAlertOK) { model.errorMessage = nil }
            } message: {
                Text(verbatim: model.errorMessage ?? "")
            }
            .onChange(of: model.errorMessage != nil) { _, showing in
                if showing, holdingShell == nil, let shell = model.shell {
                    holdingShell = shell
                    shell.beginHold(.modal)
                } else if !showing {
                    holdingShell?.endHold(.modal)
                    holdingShell = nil
                }
            }
    }

    private var isPresented: Binding<Bool> {
        Binding { model.errorMessage != nil } set: { if !$0 { model.errorMessage = nil } }
    }
}

// MARK: - Previews

/// Frames a Files preview at the anchored Hub's content size over a material, like the panel.
private struct HubFilesPreviewFrame: View {
    let model: HubFilesModel

    var body: some View {
        HubFilesView(model: model)
            .frame(width: HubStyle.anchoredSize.width, height: HubStyle.anchoredSize.height - HubStyle.headerHeight)
            .background(.regularMaterial)
            .environment(\.hubFilesIconSource, .typeOnly)
    }
}

#Preview("Split list · dark") {
    HubFilesPreviewFrame(model: .preview())
        .preferredColorScheme(.dark)
}

#Preview("Split list · light") {
    HubFilesPreviewFrame(model: .preview())
        .preferredColorScheme(.light)
}

#Preview("Icons") {
    HubFilesPreviewFrame(model: .preview(split: false, viewMode: .icons, firstLocation: "/Users/benn/Downloads"))
}

#Preview("Columns") {
    HubFilesPreviewFrame(model: .preview(split: false, viewMode: .columns))
}

#Preview("Search results") {
    HubFilesPreviewFrame(model: .preview { model in
        let source = HubFilesPreviewData.dataSource()
        model.previewOverrides.searchResults = ["/Users/benn/Downloads", "/Users/benn/Documents/DOKK/Design"]
            .flatMap { source.folders[$0] ?? [] }
            .filter { $0.name.localizedCaseInsensitiveContains("re") }
        model.query = "re"
    })
}

#Preview("Running transfer") {
    HubFilesPreviewFrame(model: .preview { model in
        model.previewOverrides.transfer = HubFilesTransferStatus(
            kind: .copy, itemCount: 3, fraction: 0.42, phase: .running,
            sourceName: "Downloads", destinationName: "Design", queuedCount: 1)
    })
}

#Preview("Empty folder") {
    HubFilesPreviewFrame(model: .preview(split: false, emptyFolders: true, firstLocation: "/Users/benn/Documents"))
}
