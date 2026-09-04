import SwiftUI
import QuickLookUI

/// A preview retains its access leases until the native Quick Look view has been dismantled.
final class DockFilePreviewItem {
    let url: URL
    private let leases: [AnyObject]

    init(url: URL, leases: [AnyObject]) {
        self.url = url
        self.leases = leases
    }
}

/// Compact Quick Look within the owning popover, with no application launch or focus transfer.
struct DockFilePreview: View {
    let item: DockFilePreviewItem
    let close: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text(verbatim: item.url.lastPathComponent).lineLimit(1)
                Spacer()
                Button(.filePreviewClose, systemImage: "xmark") { close() }
                    .labelStyle(.iconOnly)
            }
            .padding(12)
            NativeFilePreview(item: item)
        }
    }
}

private struct NativeFilePreview: NSViewRepresentable {
    let item: DockFilePreviewItem

    final class Coordinator {
        var item: DockFilePreviewItem?
    }

    func makeCoordinator() -> Coordinator { Coordinator() }

    func makeNSView(context: Context) -> QLPreviewView {
        let view = QLPreviewView(frame: .zero, style: .compact)!
        view.shouldCloseWithWindow = false
        view.autostarts = false
        return view
    }

    func updateNSView(_ view: QLPreviewView, context: Context) {
        guard context.coordinator.item !== item else { return }
        view.previewItem = item.url as NSURL
        context.coordinator.item = item
    }

    static func dismantleNSView(_ view: QLPreviewView, coordinator: Coordinator) {
        view.close()
        coordinator.item = nil
    }
}
