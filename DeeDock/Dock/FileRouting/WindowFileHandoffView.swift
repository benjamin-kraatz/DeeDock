import SwiftUI

/// Native handoff controls remain available after the selected application comes forward.
///
/// The panel reads top to bottom as one decision: this is the destination, this is the batch and
/// the handle on it, and these are the narrower actions. Nothing here delivers files on its own —
/// the footer reports what was requested, never what a destination received.
struct WindowFileHandoffView: View {
    let state: WindowFileHandoffState
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.colorScheme) private var colorScheme

    /// Every outbound action needs a validated batch and no request already in flight.
    private var enabled: Bool { state.valid && !state.busy }

    /// The destination app's own color carries the window: the wash, the chips, and the drag
    /// handle. Achromatic artwork keeps the system accent rather than inventing a hue.
    private var tint: Color {
        DockIconAccent.surface(for: state.icon, identity: state.iconIdentity,
                               dark: colorScheme == .dark) ?? .accentColor
    }

    var body: some View {
        VStack(spacing: 0) {
            if let preview = state.preview {
                DockFilePreview(item: preview) { state.preview = nil }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                content
            }
            Divider()
            WindowFileHandoffFooter(status: state.status, busy: state.busy) { state.close?() }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(nsColor: .windowBackgroundColor))
        .overlay(alignment: .top) { wash }
        .animation(reduceMotion ? nil : .easeOut(duration: 0.18), value: state.preview == nil)
    }

    private var content: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                WindowFileHandoffHeader(icon: state.icon, appName: state.appName,
                                        windowTitle: state.windowTitle, tint: tint)
                WindowFileHandoffBatchCard(state: state, tint: tint) { file in
                    state.preview = DockFilePreviewItem(url: file.url, leases: [state.documents])
                }
                actions
                failures
            }
            .padding(.horizontal, 26)
            .padding(.top, 34)
            .padding(.bottom, 24)
        }
        .scrollBounceBehavior(.basedOnSize)
    }

    private var actions: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(.fileRouteMoreActions)
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
            VStack(spacing: 2) {
                WindowFileHandoffActionRow(
                    symbol: state.windowTitle == nil ? "square.stack.3d.up" : "macwindow.on.rectangle",
                    title: state.windowTitle == nil ? .fileRouteActivateApp : .fileRouteActivateWindow,
                    subtitle: .fileRouteActivateHelp, tint: tint,
                    enabled: enabled && state.activationAvailable
                ) { state.activate?() }
                WindowFileHandoffActionRow(symbol: "doc.on.clipboard", title: .fileRouteCopy,
                                           subtitle: .fileRouteCopyHelp, tint: tint,
                                           enabled: enabled) { state.copy?() }
                    .keyboardShortcut("c", modifiers: .command)
                WindowFileHandoffActionRow(symbol: "arrow.up.forward.app", title: .fileRouteOpenApp,
                                           subtitle: .fileRouteOpenHelp, tint: tint,
                                           enabled: enabled && !state.openRequested) { state.open?() }
            }
        }
    }

    /// Filenames the app-level open request did not accept, kept verbatim and selectable so they
    /// can be retried by hand.
    @ViewBuilder private var failures: some View {
        if !state.failures.isEmpty {
            VStack(alignment: .leading, spacing: 6) {
                Label { Text(.fileRouteFailuresTitle) } icon: { Image(systemName: "exclamationmark.triangle.fill") }
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.orange)
                ForEach(state.failures, id: \.self) { failure in
                    Text(verbatim: failure)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .textSelection(.enabled)
            .padding(12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(.orange.opacity(0.10), in: .rect(cornerRadius: 12))
        }
    }

    /// The titlebar is transparent and hidden, so a wash in the destination app's own color gives
    /// the top of the window an edge without a chrome bar, and names the destination before the
    /// header is read.
    private var wash: some View {
        LinearGradient(colors: [tint.opacity(reduceTransparency ? 0 : 0.16), .clear],
                       startPoint: .top, endPoint: .bottom)
            .frame(height: 160)
            .allowsHitTesting(false)
            .accessibilityHidden(true)
    }
}

#if DEBUG
extension WindowFileHandoffState {
    /// Sample state for previews: file references that are never opened, resolved, or accessed.
    @MainActor static func previewState(
        urls: [URL] = [URL(fileURLWithPath: "/Preview/Notes/Project notes.txt"),
                       URL(fileURLWithPath: "/Preview/Screenshots/SCR-20260813-pkfs.png"),
                       URL(fileURLWithPath: "/Preview/Reports/Q3 summary.pdf")],
        appName: String = "Preview App",
        windowTitle: String? = "DeeDock — LauncherPresentationController.swift"
    ) -> WindowFileHandoffState {
        let documents = DocumentResourceAccess(urls, startAccess: { _ in false }, stopAccess: { _ in })
        return WindowFileHandoffState(documents: documents, appName: appName, windowTitle: windowTitle,
                                      icon: NSImage(systemSymbolName: "app.dashed", accessibilityDescription: nil)!,
                                      iconIdentity: "preview.\(appName)")
    }
}

#Preview("File handoff · exact destination") {
    let state = WindowFileHandoffState.previewState()
    state.busy = false
    state.valid = true
    state.status = .ready
    return WindowFileHandoffView(state: state).frame(width: 540, height: 720)
}

#Preview("File handoff · unavailable source") {
    let state = WindowFileHandoffState.previewState(
        urls: [URL(fileURLWithPath: "/Preview/Unavailable.txt")], windowTitle: nil)
    state.busy = false
    state.activationAvailable = false
    state.status = .invalid
    return WindowFileHandoffView(state: state).frame(width: 540, height: 720)
}

#Preview("File handoff · partial open, German") {
    let state = WindowFileHandoffState.previewState()
    state.busy = false
    state.valid = true
    state.openRequested = true
    state.status = .openResult(submitted: 2, total: 3)
    state.failures = ["Q3 summary.pdf: The application cannot open this document."]
    return WindowFileHandoffView(state: state)
        .environment(\.locale, Locale(identifier: "de"))
        .frame(width: 540, height: 720)
}

#Preview("File handoff · checking") {
    let state = WindowFileHandoffState.previewState()
    return WindowFileHandoffView(state: state).preferredColorScheme(.dark).frame(width: 540, height: 720)
}
#endif
