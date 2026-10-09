import QuickLookUI
import SwiftUI

/// A Quick Look preview of one file inside the preview well.
///
/// The URL is handed to `QLPreviewView` after a short pause, so arrowing through a folder does
/// not start a preview for every item passed over. Previews (`.typeOnly` icon source) show the
/// type icon instead and never read the file.
struct HubFilesQuickLookWell: View {
    let item: HubFileItem

    @Environment(\.hubFilesIconSource) private var source
    @State private var shownURL: URL?

    var body: some View {
        ZStack {
            HubFilesItemIcon(item: item, size: 110, thumbnail: true)
                .opacity(shownURL == nil ? 1 : 0)
            if source == .live, let shownURL {
                HubFilesNativeQuickLook(url: shownURL)
                    .padding(8)
            }
        }
        .task(id: item.url) {
            shownURL = nil
            guard source == .live else { return }
            try? await Task.sleep(for: .milliseconds(140))
            guard !Task.isCancelled else { return }
            shownURL = item.url
        }
    }
}

/// `QLPreviewView` in compact style, without controls or focus changes.
private struct HubFilesNativeQuickLook: NSViewRepresentable {
    let url: URL

    func makeNSView(context: Context) -> QLPreviewView {
        let view = QLPreviewView(frame: .zero, style: .compact)!
        view.shouldCloseWithWindow = false
        view.autostarts = false
        return view
    }

    func updateNSView(_ view: QLPreviewView, context: Context) {
        guard (view.previewItem as? NSURL) as URL? != url else { return }
        view.previewItem = url as NSURL
    }

    static func dismantleNSView(_ view: QLPreviewView, coordinator: ()) {
        view.close()
    }
}
