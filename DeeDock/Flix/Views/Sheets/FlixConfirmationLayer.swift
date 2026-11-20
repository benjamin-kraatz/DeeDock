import SwiftUI

/// The question asked before items leave for another app: a sensitive file, or an older version.
///
/// Shown in the panel because the question runs at drag start (see `FlixCoordinator.beginDrag`).
/// Answering lets the next drag of the same items go ahead; the toast says so.
struct FlixConfirmationLayer: View {
    let state: FlixPanelState

    var body: some View {
        ZStack {
            if let pending = state.confirmation {
                Color.black.opacity(0.18)
                    .onTapGesture { state.confirmation = nil }
                    .accessibilityHidden(true)
                FlixConfirmationDialog(pending: pending, state: state)
                    .transition(state.reduceMotion ? .opacity : .scale(scale: 0.9).combined(with: .opacity))
            }
        }
        .animation(state.reduceMotion ? .easeOut(duration: 0.15) : .spring(response: 0.3, dampingFraction: 0.7),
                   value: state.confirmation)
    }
}

private struct FlixConfirmationDialog: View {
    let pending: FlixPendingConfirmation
    let state: FlixPanelState

    var body: some View {
        VStack(spacing: 8) {
            Image(systemName: symbol).font(.system(size: 28)).foregroundStyle(Color.accentColor)
            Text(title).font(.system(size: 13.5, weight: .semibold)).multilineTextAlignment(.center)
            Text(message).font(.system(size: 12)).foregroundStyle(.secondary).multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
            VStack(spacing: 6) { buttons }
                .padding(.top, 4)
        }
        .padding(16)
        .frame(width: 300)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).strokeBorder(Color.primary.opacity(0.15), lineWidth: 0.5))
        .shadow(color: .black.opacity(0.35), radius: 24, y: 12)
        .accessibilityElement(children: .contain)
        .accessibilityAddTraits(.isModal)
    }

    private var symbol: String {
        if case .sensitive = pending.confirmation { return "lock.shield" }
        return "doc.on.doc"
    }

    private func name(_ id: FlixItem.ID) -> String { state.history.item(id)?.name ?? "" }

    private var title: String {
        switch pending.confirmation {
        case .sensitive: String(localized: .flixConfirmSensitiveTitle)
        case .newerVersion: String(localized: .flixConfirmNewerTitle)
        }
    }

    private var message: String {
        switch pending.confirmation {
        case .sensitive(let id, let reason, let destination):
            let base = destination.map { String(localized: .flixConfirmSensitiveMessageTo(name(id), $0)) }
                ?? String(localized: .flixConfirmSensitiveMessage(name(id)))
            return reason.map { $0 + " " + base } ?? base
        case .newerVersion(let id, let newer):
            return String(localized: .flixConfirmNewerMessage(name(newer), name(id)))
        }
    }

    @ViewBuilder private var buttons: some View {
        switch pending.confirmation {
        case .sensitive:
            dialogButton(String(localized: .flixConfirmSendAnyway)) { confirm(pending.itemIDs) }
            dialogButton(String(localized: .flixCancel), primary: true) { state.confirmation = nil }
        case .newerVersion(let id, let newer):
            dialogButton(String(localized: .flixConfirmUseNewer(name(newer))), primary: true) {
                let ids = pending.itemIDs.map { $0 == id ? newer : $0 }
                state.selection = Set(ids)
                state.cursor = newer
                confirm(ids)
            }
            dialogButton(String(localized: .flixConfirmSendOlder(name(id)))) { confirm(pending.itemIDs) }
        }
    }

    private func dialogButton(_ title: String, primary: Bool = false, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(verbatim: title)
                .lineLimit(1)
                .truncationMode(.middle)
                .frame(maxWidth: .infinity)
                .frame(height: 28)
                .foregroundStyle(primary ? Color.white : .primary)
                .background(primary ? Color.accentColor : FlixStyle.chipHover,
                            in: RoundedRectangle(cornerRadius: 8, style: .continuous))
        }
        .buttonStyle(.plain)
        .font(.system(size: 12.5))
    }

    private func confirm(_ ids: [FlixItem.ID]) {
        state.confirmation = nil
        state.confirmDrag?(ids)
        state.showToast(String(localized: .flixToastDragAgain))
    }
}
