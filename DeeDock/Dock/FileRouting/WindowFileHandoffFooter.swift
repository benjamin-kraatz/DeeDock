import SwiftUI

/// What just happened, and the one control that ends the session and releases the file grants.
struct WindowFileHandoffFooter: View {
    let status: WindowFileHandoffStatus
    /// A request is in flight; the spinner replaces the status symbol rather than joining it.
    let busy: Bool
    let close: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .firstTextBaseline, spacing: 9) {
                indicator
                Text(status.message)
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                    .textSelection(.enabled)
                Spacer(minLength: 0)
            }
            .accessibilityElement(children: .combine)
            HStack {
                Spacer(minLength: 0)
                Button(.fileRouteClose, action: close)
                    .buttonStyle(.borderedProminent)
                    .controlSize(.large)
                    .keyboardShortcut(.cancelAction)
            }
        }
        .padding(.horizontal, 24)
        .padding(.vertical, 18)
    }

    private var indicator: some View {
        Group {
            if busy {
                ProgressView().controlSize(.small)
            } else {
                Image(systemName: status.symbol)
                    .foregroundStyle(status.tone.color)
            }
        }
        .frame(width: 16)
        .accessibilityHidden(true)
    }
}

#if DEBUG
#Preview("Ready") {
    WindowFileHandoffFooter(status: .ready, busy: false, close: {}).frame(width: 540)
}

#Preview("Checking") {
    WindowFileHandoffFooter(status: .checking, busy: true, close: {}).frame(width: 540)
}

#Preview("Partial open, German") {
    WindowFileHandoffFooter(status: .openResult(submitted: 2, total: 4), busy: false, close: {})
        .environment(\.locale, Locale(identifier: "de"))
        .frame(width: 540)
}
#endif
