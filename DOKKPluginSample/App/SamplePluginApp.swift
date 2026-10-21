// DOKK Sample Plugin: a developer example, never shipped with DOKK. See docs/PLUGINS.md.
// Its copy is plain English on purpose: it is sample code, not part of DOKK's interface.

import SwiftUI

/// The app that carries the sample plugin, `DOKK Sample Plugin Extension.appex`, in
/// `Contents/Extensions`. Installing it is what makes the plugin known to macOS; it has nothing
/// else to do.
@main
struct SamplePluginApp: App {
    var body: some Scene {
        Window(Text(verbatim: "DOKK Sample Plugin"), id: "main") {
            SamplePluginAppView()
        }
        .windowResizability(.contentSize)
    }
}

/// Explains where the plugin shows up and how to turn it on.
struct SamplePluginAppView: View {
    var body: some View {
        VStack(spacing: 12) {
            Image(systemName: "puzzlepiece.extension.fill")
                .font(.system(size: 40))
                .foregroundStyle(.tint)
                .accessibilityHidden(true)
            Text(verbatim: "DOKK Sample Plugin")
                .font(.title2.weight(.semibold))
            Text(verbatim: "This app adds a sample plugin to DOKK. In DOKK, open Settings › Plugins and choose Manage Plugins… to turn it on. Its tile then appears in the dock.")
                .multilineTextAlignment(.center)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(32)
        .frame(width: 380)
    }
}

#Preview {
    SamplePluginAppView()
}
