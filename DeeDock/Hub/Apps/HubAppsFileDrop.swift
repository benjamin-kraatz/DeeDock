import AppKit
import SwiftUI

/// Accepts files dropped onto the open Apps tab and starts file actions with them, the same path
/// as a drop on the DOKK tile (``HubAppsModel/adoptFiles(_:)``). Shows a subtle accent wash and
/// outline while a file drag is over the tab.
struct HubAppsFileDrop: ViewModifier {
    let model: HubAppsModel

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var isTargeted = false

    func body(content: Content) -> some View {
        content
            .overlay {
                if isTargeted {
                    RoundedRectangle(cornerRadius: HubAppsStyle.tileCornerRadius, style: .continuous)
                        .fill(Color.accentColor.opacity(0.06))
                        .strokeBorder(Color.accentColor.opacity(0.55), lineWidth: 2)
                        .padding(6)
                        .allowsHitTesting(false)
                        .transition(.opacity)
                }
            }
            .animation(reduceMotion ? nil : .easeOut(duration: 0.15), value: isTargeted)
            .dropDestination(for: URL.self) { urls, _ in
                let files = urls.filter(\.isFileURL)
                guard !files.isEmpty else { return false }
                // Reuse an in-process lease (a drag from a DOKK stack, Shelf, or the Files tab) so
                // nested items keep their parent folder's security scope; otherwise take a new grant.
                let access = DocumentDragLeaseRegistry.access(for: NSPasteboard(name: .drag), urls: files)
                model.adoptFiles(.owned(access, source: .drop))
                return true
            } isTargeted: { isTargeted = $0 }
    }
}
