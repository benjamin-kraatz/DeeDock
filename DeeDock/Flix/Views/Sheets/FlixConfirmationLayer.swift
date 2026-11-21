import SwiftUI

/// The question asked before items leave for another app: a sensitive file, or an older version.
///
/// Shown in the panel because the question runs at drag start (see `FlixCoordinator.beginDrag`).
/// Answering lets the next drag past that question go ahead; the toast says so. When the items
/// still have another question (a newer version swapped in that is itself flagged), that question
/// shows next instead of the toast. The dialog scales
/// in from 90 % with ``FlixMotion/dialog``; with Reduce Motion it crossfades.
struct FlixConfirmationLayer: View {
    let state: FlixPanelState

    var body: some View {
        ZStack {
            if let pending = state.confirmation {
                Color.black.opacity(0.22)
                    .onTapGesture { state.confirmation = nil }
                    .transition(.opacity)
                    .accessibilityHidden(true)
                FlixConfirmationDialog(pending: pending, state: state)
                    .transition(state.reduceMotion ? .opacity : .scale(scale: 0.9).combined(with: .opacity))
                    .id(pending.id)
            }
        }
        .animation(FlixMotion.resolved(FlixMotion.dialog, reduceMotion: state.reduceMotion), value: state.confirmation)
    }
}

/// The dialog itself: a tinted symbol, the question, and stacked buttons.
private struct FlixConfirmationDialog: View {
    let pending: FlixPendingConfirmation
    let state: FlixPanelState

    var body: some View {
        VStack(spacing: 8) {
            FlixDialogSymbol(name: symbol, tint: isSensitive ? .orange : .accentColor)
                .padding(.bottom, 2)
            Text(title)
                .font(.system(size: 13.5, weight: .semibold))
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
                .accessibilityAddTraits(.isHeader)
            Text(message)
                .font(.system(size: 12))
                .lineSpacing(2)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
            VStack(spacing: 6) { buttons }
                .padding(.top, 6)
        }
        .padding(16)
        .frame(width: 300)
        .modifier(FlixFloatingSurface())
        .accessibilityElement(children: .contain)
        .accessibilityAddTraits(.isModal)
    }

    private var isSensitive: Bool {
        if case .sensitive = pending.confirmation { return true }
        return false
    }

    private var symbol: String { isSensitive ? "lock.shield.fill" : "doc.on.doc.fill" }

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
        case .sensitive(let id, _, _):
            dialogButton(String(localized: .flixConfirmSendAnyway)) { confirm(pending.itemIDs, .sendAnyway) }
            if let markNotSensitive = state.markNotSensitive {
                dialogButton(String(localized: .flixConfirmNotSensitive)) { markNotSensitive(id) }
            }
            dialogButton(String(localized: .flixCancel), primary: true) { state.confirmation = nil }
        case .newerVersion(let id, let newer):
            dialogButton(String(localized: .flixConfirmUseNewer(name(newer))), primary: true) {
                let ids = pending.itemIDs.map { $0 == id ? newer : $0 }
                state.selection = Set(ids)
                state.cursor = newer
                confirm(ids, .useNewest)
            }
            dialogButton(String(localized: .flixConfirmSendOlder(name(id)))) { confirm(pending.itemIDs, .sendAnyway) }
        }
    }

    private func dialogButton(_ title: String, primary: Bool = false, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(verbatim: title)
                .font(.system(size: 12.5, weight: primary ? .semibold : .regular))
                .lineLimit(1)
                .truncationMode(.middle)
        }
        .buttonStyle(FlixCardButtonStyle(primary: primary, expands: true, height: 28, radius: 8))
        .help(Text(verbatim: title))
    }

    private func confirm(_ ids: [FlixItem.ID], _ resolution: AnalyticsFlixWarningResolution) {
        // A follow-up question replaces the dialog; only a drag with nothing left to ask gets the toast.
        guard !state.resolveConfirmation(resolution, ids: ids) else { return }
        state.showToast(String(localized: .flixToastDragAgain))
    }
}

/// The dialog's symbol on a soft disc of its tint.
private struct FlixDialogSymbol: View {
    let name: String
    let tint: Color

    var body: some View {
        Image(systemName: name)
            .font(.system(size: 20, weight: .medium))
            .foregroundStyle(tint)
            .frame(width: 44, height: 44)
            .background(tint.opacity(0.15), in: .circle)
            .accessibilityHidden(true)
    }
}

#if DEBUG
#Preview("Sensitive question") {
    FlixPanelView(state: FlixPreviewData.panelState(.sensitiveQuestion)).frame(width: 760, height: 608)
}

#Preview("Newer version question, German, light") {
    FlixPanelView(state: FlixPreviewData.panelState(.newerVersionQuestion)).frame(width: 760, height: 608)
        .environment(\.locale, Locale(identifier: "de"))
        .preferredColorScheme(.light)
}
#endif
