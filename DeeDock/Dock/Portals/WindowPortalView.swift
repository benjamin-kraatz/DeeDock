import SwiftUI

/// The portal panel: the captured window, what it is doing, and the controls that act on it.
///
/// The frame is the panel. Status and controls float over it on glass instead of taking rows of
/// their own, so a small portal spends its pixels on the window being watched rather than on
/// chrome. The controls appear on hover, while the panel holds the keyboard, and whenever there is
/// no frame to obstruct; every one of them is also in the context menu, so nothing needs a pointer.
///
/// View-and-jump controls deliberately do not forward clicks into the captured application.
struct WindowPortalView: View {
    @Bindable var state: WindowPortalState
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.controlActiveState) private var activeState
    @State private var hovering = false
    @State private var viewportControls = false

    /// The source app's own color, so a portal is recognizably about that application.
    private var tint: Color {
        guard let icon = state.icon else { return .accentColor }
        return DockIconAccent.surface(for: icon, identity: state.appName, dark: colorScheme == .dark) ?? .accentColor
    }

    /// Controls are shown when the pointer is over the portal, when the panel has the keyboard, and
    /// whenever there is no frame to obstruct. Keyboard-only operation never depends on a hover.
    private var controlsVisible: Bool {
        hovering || viewportControls || activeState == .key || state.image == nil || state.needsReselection
    }

    var body: some View {
        frame
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .overlay(alignment: .top) { statusBar }
            .overlay(alignment: .bottom) { controls }
            .background(reduceTransparency ? AnyShapeStyle(Color(nsColor: .windowBackgroundColor))
                                           : AnyShapeStyle(.regularMaterial))
            .tint(tint)
            .onHover { hovering = $0 }
            .animation(reduceMotion ? nil : .snappy(duration: 0.18), value: controlsVisible)
            .animation(reduceMotion ? nil : .snappy(duration: 0.22), value: state.phase)
            .sheet(isPresented: $state.editingCrop) { WindowPortalCropEditor(state: state) }
            .contextMenu { WindowPortalMenu(state: state) }
            .accessibilityElement(children: .contain)
            .accessibilityLabel(Text(verbatim: state.sourceName))
            .accessibilityHint(Text(.portalKeyboardHelp))
            .accessibilityAction(named: Text(.portalJump)) { state.jump?() }
            .accessibilityAction(named: Text(.portalSave)) { state.saveFrame?() }
            .accessibilityAction(named: Text(.portalClose)) { state.close?() }
            .accessibilityAction(named: Text(.portalMoveLeft)) { state.move?(-20, 0) }
            .accessibilityAction(named: Text(.portalMoveRight)) { state.move?(20, 0) }
            .accessibilityAction(named: Text(.portalMoveUp)) { state.move?(0, 20) }
            .accessibilityAction(named: Text(.portalMoveDown)) { state.move?(0, -20) }
    }

    // MARK: Frame

    @ViewBuilder private var frame: some View {
        Group {
            if state.needsReselection {
                ContentUnavailableView {
                    Label(.portalReselect, systemImage: "crop")
                } actions: {
                    Button(.portalCrop) { state.editCrop?() }
                    Button(.portalWholeWindow) { state.applyCrop(NormalizedWindowRegion()) }
                }
            } else if let image = state.image {
                WindowPortalContent(state: state, image: image)
            } else {
                ContentUnavailableView {
                    Label(state.phase.label, systemImage: state.phase.symbol)
                }
            }
        }
        .accessibilityLabel(Text(verbatim: state.sourceName))
        .accessibilityValue(Text(state.phase.label))
    }

    // MARK: Status

    /// Phase on the left, the moment the frame was taken on the right — the two questions a glance
    /// at a portal asks. Both stay legible over arbitrary window content by sitting on glass.
    private var statusBar: some View {
        HStack(alignment: .top) {
            phasePill
            Spacer(minLength: 6)
            if let date = state.lastFrameAt {
                Text(date, format: .dateTime.hour().minute().second())
                    .font(.caption2.monospacedDigit())
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 8).padding(.vertical, 4)
                    .modifier(PortalChrome(opaque: reduceTransparency))
                    .accessibilityLabel(Text(.portalCapturedAt))
                    .accessibilityValue(Text(date, format: .dateTime.hour().minute().second()))
            }
        }
        .padding(8)
        .allowsHitTesting(false)
    }

    private var phasePill: some View {
        HStack(spacing: 5) {
            Image(systemName: state.phase.symbol)
                .imageScale(.small)
                .symbolEffect(.pulse, isActive: state.phase.isStreaming && !reduceMotion)
            Text(state.phase.label).lineLimit(1)
        }
        .font(.caption2.weight(.semibold))
        .foregroundStyle(state.phase.color)
        .padding(.horizontal, 8).padding(.vertical, 4)
        .modifier(PortalChrome(opaque: reduceTransparency))
        .accessibilityElement(children: .combine)
    }

    // MARK: Controls

    private var controls: some View {
        VStack(spacing: 6) {
            if state.jumpFailed { notice(.portalJumpFallback) }
            if state.exportFailed { notice(.portalSaveFailed) }
            WindowPortalToolbar(state: state, opaque: reduceTransparency,
                                viewportControls: $viewportControls)
                .opacity(controlsVisible ? 1 : 0)
                .allowsHitTesting(controlsVisible)
        }
        .padding(8)
    }

    private func notice(_ text: LocalizedStringResource) -> some View {
        Text(text)
            .font(.caption2)
            .multilineTextAlignment(.center)
            .fixedSize(horizontal: false, vertical: true)
            .padding(.horizontal, 8).padding(.vertical, 4)
            .modifier(PortalChrome(opaque: reduceTransparency))
    }
}

/// The one surface every floating portal control sits on, so status and toolbar match.
struct PortalChrome: ViewModifier {
    let opaque: Bool

    func body(content: Content) -> some View {
        if opaque {
            content.background(Color(nsColor: .windowBackgroundColor), in: .capsule)
                .overlay { Capsule().strokeBorder(.separator) }
        } else {
            content.glassEffect(.regular, in: .capsule)
        }
    }
}

#if DEBUG
/// A deterministic stand-in for a captured window, so previews need no capture service or permission.
@MainActor private func portalPreviewImage() -> CGImage? {
    guard let context = CGContext(data: nil, width: 640, height: 400, bitsPerComponent: 8, bytesPerRow: 0,
                                  space: CGColorSpaceCreateDeviceRGB(),
                                  bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return nil }
    context.setFillColor(NSColor.controlBackgroundColor.cgColor)
    context.fill(CGRect(x: 0, y: 0, width: 640, height: 400))
    context.setFillColor(NSColor.systemIndigo.withAlphaComponent(0.5).cgColor)
    context.fill(CGRect(x: 0, y: 352, width: 640, height: 48))
    context.setFillColor(NSColor.systemGray.withAlphaComponent(0.35).cgColor)
    for row in 0..<6 { context.fill(CGRect(x: 40, y: 60 + row * 40, width: 380, height: 16)) }
    return context.makeImage()
}

@MainActor private func portalPreviewState(_ configure: (WindowPortalState) -> Void) -> WindowPortalState {
    let state = WindowPortalState(appName: "Xcode", source: ApplicationWindowSummary(
        token: ApplicationWindowToken(sessionID: UUID(), id: UUID()), processIdentifier: 0,
        title: "DeeDock — DeeDock.xcodeproj", frame: CGRect(x: 0, y: 0, width: 640, height: 400),
        isMinimized: false, isMain: false))
    configure(state)
    return state
}

#Preview("Live portal") {
    WindowPortalView(state: portalPreviewState {
        $0.image = portalPreviewImage()
        $0.phase = .live
        $0.lastFrameAt = .now
    }).frame(width: 380, height: 280)
}

#Preview("Paused portal") {
    WindowPortalView(state: portalPreviewState { $0.phase = .paused })
        .frame(width: 380, height: 280)
}

#Preview("Needs reselection") {
    WindowPortalView(state: portalPreviewState {
        $0.image = portalPreviewImage()
        $0.needsReselection = true
        $0.phase = .reselect
    }).frame(width: 380, height: 280)
}
#endif
