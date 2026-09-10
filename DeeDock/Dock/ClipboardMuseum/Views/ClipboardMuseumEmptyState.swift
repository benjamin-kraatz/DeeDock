import SwiftUI

/// The empty museum. Offers to start collecting when it is off, since that is the only way in.
struct ClipboardMuseumEmptyState: View {
    let captureEnabled: Bool
    let requiresReset: Bool
    let enableCapture: () -> Void

    var body: some View {
        ContentUnavailableView {
            Label { Text(.clipboardMuseumEmptyTitle) } icon: { Image(systemName: "building.columns") }
        } description: {
            Text(requiresReset ? .clipboardMuseumResetHelp
                 : captureEnabled ? .clipboardMuseumEmptyOn : .clipboardMuseumEmptyOff)
        } actions: {
            if !captureEnabled, !requiresReset {
                Button(action: enableCapture) { Text(.clipboardMuseumStartCollecting) }
                    .buttonStyle(.borderedProminent)
            }
        }
    }
}

#if DEBUG
#Preview("Collecting off") {
    ClipboardMuseumEmptyState(captureEnabled: false, requiresReset: false, enableCapture: {})
        .frame(width: 520, height: 400)
}

#Preview("Collecting on") {
    ClipboardMuseumEmptyState(captureEnabled: true, requiresReset: false, enableCapture: {})
        .frame(width: 520, height: 400)
}
#endif
