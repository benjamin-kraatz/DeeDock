import AppKit
import SwiftUI

/// Names the destination the batch was aimed at, so the panel is recognizable when it is the only
/// thing left on screen after Peek closes.
///
/// An app-level destination is already named by the app title, so it says so in one line rather
/// than repeating the name in a card of its own. An exact window is different: its title is the
/// only place the chosen window is identified.
struct WindowFileHandoffHeader: View {
    let icon: NSImage
    let appName: String
    /// Present only when an exact accessible window was chosen; otherwise the destination is the app.
    let windowTitle: String?
    /// Dominant color of the destination app's icon, or the system accent for achromatic artwork.
    let tint: Color

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(spacing: 14) {
                Image(nsImage: icon)
                    .resizable().interpolation(.high).scaledToFit()
                    .frame(width: 56, height: 56)
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 3) {
                    Text(.fileRouteTitle)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                    Text(verbatim: appName)
                        .font(.system(size: 24, weight: .semibold, design: .rounded))
                        .lineLimit(2)
                        .accessibilityAddTraits(.isHeader)
                    if windowTitle == nil { scope }
                }
                Spacer(minLength: 0)
            }
            if windowTitle != nil { window }
            Text(.fileRouteHandoffHelp)
                .font(.callout)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    /// App-level handoff: one line under the name, because the name is the destination.
    private var scope: some View {
        Label { Text(.fileRouteAppDestination) } icon: { Image(systemName: "square.stack.3d.up") }
            .font(.caption)
            .foregroundStyle(.secondary)
            .accessibilityElement(children: .combine)
    }

    /// Exact window handoff: the chosen window's title, which nothing else in the panel states.
    private var window: some View {
        HStack(spacing: 11) {
            Image(systemName: "macwindow")
                .font(.system(size: 14, weight: .medium))
                .foregroundStyle(tint)
                .frame(width: 30, height: 30)
                .background(tint.opacity(0.14), in: .rect(cornerRadius: 9))
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 2) {
                Text(.fileRouteWindowDestination)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Text(verbatim: windowTitle ?? appName)
                    .font(.callout.weight(.medium))
                    .lineLimit(2)
            }
            Spacer(minLength: 0)
        }
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.quaternary.opacity(0.6), in: .rect(cornerRadius: 12))
        .accessibilityElement(children: .combine)
    }
}

#if DEBUG
#Preview("Exact window") {
    WindowFileHandoffHeader(icon: NSImage(systemSymbolName: "app.dashed", accessibilityDescription: nil)!,
                            appName: "Preview App",
                            windowTitle: "A long destination window title for layout inspection",
                            tint: .accentColor)
        .padding(26).frame(width: 540)
}

#Preview("App-level, German") {
    WindowFileHandoffHeader(icon: NSImage(systemSymbolName: "app.dashed", accessibilityDescription: nil)!,
                            appName: "Preview App", windowTitle: nil, tint: .teal)
        .environment(\.locale, Locale(identifier: "de"))
        .padding(26).frame(width: 540)
}
#endif
