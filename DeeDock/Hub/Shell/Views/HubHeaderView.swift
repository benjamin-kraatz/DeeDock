import SwiftUI

/// What the header's controls do. The coordinator supplies real actions; previews pass no-ops.
struct HubHeaderActions {
    /// A click on a switcher segment.
    var select: (HubTab) -> Void
    /// The pin button: detach while anchored, attach while detached.
    var togglePin: () -> Void
    var close: () -> Void
}

/// The 58-point header: wordmark, tab switcher, search field, pin, and close.
///
/// Laid out like the mockup's three-column grid: the switcher stays centered however wide the
/// sides are. While detached, the leading side leaves room for the window's traffic lights, which
/// `HubPanelController` places on the header, and the header doubles as the title bar: dragging
/// anywhere on it that is not a control moves the window.
struct HubHeaderView: View {
    let state: HubShellState
    @Binding var query: String
    let prompt: LocalizedStringResource
    let actions: HubHeaderActions

    /// Width the detached window's traffic lights take before the wordmark: three 12-point lights
    /// with 8-point gaps, then the mockup's 4 + 12 points of spacing.
    private static let trafficLightsWidth: CGFloat = 68

    var body: some View {
        HStack(spacing: 12) {
            HStack(spacing: 0) {
                if state.isDetached {
                    Color.clear.frame(width: Self.trafficLightsWidth, height: 1)
                        .accessibilityHidden(true)
                }
                HubWordmark()
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            HubTabSwitcher(selection: state.tab, reduceMotion: state.reduceMotion, select: actions.select)

            HStack(spacing: 6) {
                HubSearchField(query: $query, prompt: prompt, state: state)
                HubHeaderButton(symbol: state.isDetached ? "pin.slash" : "pin",
                                label: state.isDetached ? .hubAttachHelp : .hubPinHelp,
                                action: actions.togglePin)
                HubHeaderButton(symbol: "xmark", label: .hubCloseHelp, action: actions.close)
            }
            .frame(maxWidth: .infinity, alignment: .trailing)
        }
        .padding(.leading, 20)
        .padding(.trailing, 14)
        .frame(height: HubStyle.headerHeight)
        .contentShape(.rect)
        // Controls keep their own clicks: a child's gesture wins over this one. The wordmark and
        // the empty header space move the window, as the mockup's header does.
        .gesture(WindowDragGesture(), isEnabled: state.isDetached)
    }
}

/// The DOKK logotype in the header: heavy, slightly tracked, in the primary text color.
private struct HubWordmark: View {
    var body: some View {
        Text(.appName)
            .font(.system(size: 21, weight: .heavy))
            .tracking(21 * 0.06)
            .foregroundStyle(.primary)
            .lineLimit(1)
            .fixedSize()
            .accessibilityAddTraits(.isHeader)
    }
}

#Preview("Header, anchored") {
    @Previewable @State var query = ""
    HubHeaderView(state: HubShellState(tab: .apps), query: $query, prompt: .hubTabApps,
                  actions: HubHeaderActions(select: { _ in }, togglePin: {}, close: {}))
        .frame(width: 1180)
}

#Preview("Header, detached") {
    @Previewable @State var query = "Notes"
    HubHeaderView(state: .preview(tab: .files, detached: true), query: $query, prompt: .hubTabFiles,
                  actions: HubHeaderActions(select: { _ in }, togglePin: {}, close: {}))
        .frame(width: 1000)
}
