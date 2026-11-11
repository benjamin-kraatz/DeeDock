import SwiftUI

/// The capsule above the orb: a refusal, the delete status with countdown and Undo, "Drop to
/// add", or the hover tooltip. ``VaporController/callout`` decides which.
///
/// Each new callout pops in (rises a few points and scales up). When the callout goes away,
/// the last one stays drawn so the window can fade it out.
struct VaporCalloutView: View {
    let controller: VaporController

    /// Transparent room around the capsule for its shadow and pop-in. The window is placed so
    /// the capsule itself, not this margin, sits at the geometry's frame.
    static let margin: CGFloat = 18

    @State private var lastCallout: VaporCallout?

    var body: some View {
        Group {
            if let callout = controller.callout ?? lastCallout {
                VaporCalloutContent(callout: callout, reduceTransparency: controller.reduceTransparency,
                                    undo: { controller.undo() })
                    .modifier(VaporPopIn(reduceMotion: controller.reduceMotion))
                    .id(callout.identity)
                    .fixedSize()
                    .padding(Self.margin)
            }
        }
        .onChange(of: controller.callout, initial: true) { _, callout in
            if let callout { lastCallout = callout }
        }
    }
}

private extension VaporCallout {
    /// Changes when a different capsule should pop in; stays put while one capsule updates
    /// (the tooltip's size arriving, for example).
    var identity: String {
        switch self {
        case .refusal: "refusal"
        // "Freed…" and "Put back…" keep the token of the "Deleted…" capsule they follow, so
        // its text changes in place.
        case .status(let status): "status-\(status.token)"
        case .dropToAdd: "drop"
        case .tooltip: "tooltip"
        }
    }
}

/// Rises 6 pt and scales up from 96 % with a little overshoot. A fade under Reduce Motion.
private struct VaporPopIn: ViewModifier {
    let reduceMotion: Bool
    @State private var shown = false

    func body(content: Content) -> some View {
        content
            .opacity(shown ? 1 : 0)
            .scaleEffect(shown || reduceMotion ? 1 : 0.96, anchor: .bottom)
            .offset(y: shown || reduceMotion ? 0 : 6)
            .onAppear {
                withAnimation(reduceMotion ? .easeOut(duration: 0.15) : VaporMotion.capsuleEnter) { shown = true }
            }
    }
}

private struct VaporCalloutContent: View {
    let callout: VaporCallout
    let reduceTransparency: Bool
    let undo: () -> Void

    var body: some View {
        switch callout {
        case .tooltip(let totals):
            Text(verbatim: VaporCopy.summary(totals))
                .monospacedDigit()
                .modifier(VaporTooltipChrome(reduceTransparency: reduceTransparency, accent: false))
        case .dropToAdd:
            Text(.vaporTooltipDropToAdd)
                .modifier(VaporTooltipChrome(reduceTransparency: reduceTransparency, accent: true))
        case .refusal(let refusal):
            HStack(spacing: 10) {
                VaporStatusIcon(kind: .refused)
                Text(VaporCopy.refusal(refusal))
            }
            .modifier(VaporCapsuleChrome(reduceTransparency: reduceTransparency, trailing: 13))
        case .status(let status):
            VaporStatusCapsule(kind: status.kind, reduceTransparency: reduceTransparency, undo: undo)
        }
    }
}

/// The delete status: "Deleted 3 folders" with the countdown ring and Undo, then
/// "✓ Freed 1.8 GB", "Put back 3 folders" after Undo, or a failure.
private struct VaporStatusCapsule: View {
    let kind: VaporStatus.Kind
    let reduceTransparency: Bool
    let undo: () -> Void

    var body: some View {
        HStack(spacing: 10) {
            switch kind {
            case .deleted(_, _, let deadline):
                Text(verbatim: VaporCopy.status(kind))
                VaporCountdownRing(deadline: deadline)
                Button(.vaporUndo, action: undo)
                    .buttonStyle(VaporUndoButtonStyle())
            case .freed:
                VaporStatusIcon(kind: .done)
                Text(verbatim: VaporCopy.status(kind))
                    .padding(.trailing, 6)
            case .restored:
                Text(verbatim: VaporCopy.status(kind))
                    .padding(.trailing, 6)
            case .failed, .notRestored:
                VaporStatusIcon(kind: .refused)
                Text(verbatim: VaporCopy.status(kind))
                    .padding(.trailing, 6)
            }
        }
        .modifier(VaporCapsuleChrome(reduceTransparency: reduceTransparency, trailing: isDeleted ? 8 : 13))
        .accessibilityElement(children: .combine)
    }

    private var isDeleted: Bool {
        if case .deleted = kind { return true }
        return false
    }
}

/// A round 18 pt status mark: a green check, or a red ×.
private struct VaporStatusIcon: View {
    enum Kind { case done, refused }
    let kind: Kind

    var body: some View {
        Image(systemName: kind == .done ? "checkmark" : "xmark")
            .font(.system(size: 9, weight: .heavy))
            .foregroundStyle(.white)
            .frame(width: 18, height: 18)
            .background(kind == .done ? VaporStyle.success : VaporStyle.danger, in: .circle)
            .accessibilityHidden(true)
    }
}

/// The capsule look: glass (or opaque under Reduce Transparency), a hairline and a soft shadow.
private struct VaporCapsuleChrome: ViewModifier {
    let reduceTransparency: Bool
    let trailing: CGFloat

    func body(content: Content) -> some View {
        content
            .font(.system(size: 12.5, weight: .medium))
            .lineLimit(1)
            .padding(EdgeInsets(top: 7, leading: 13, bottom: 7, trailing: trailing))
            .vaporGlass(in: RoundedRectangle(cornerRadius: 14, style: .continuous), reduceTransparency: reduceTransparency)
            .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).strokeBorder(VaporStyle.line2, lineWidth: 0.5))
            .shadow(color: .black.opacity(0.22), radius: 15, y: 10)
    }
}

/// The small tooltip look; `accent` is the blue "Drop to add".
private struct VaporTooltipChrome: ViewModifier {
    let reduceTransparency: Bool
    let accent: Bool

    func body(content: Content) -> some View {
        let shape = RoundedRectangle(cornerRadius: 9, style: .continuous)
        content
            .font(.system(size: 12, weight: .medium))
            .lineLimit(1)
            .foregroundStyle(accent ? AnyShapeStyle(.white) : AnyShapeStyle(.primary))
            .padding(.horizontal, 10)
            .padding(.vertical, 5)
            .background {
                if accent {
                    shape.fill(Color.accentColor)
                } else {
                    Color.clear.vaporGlass(in: shape, reduceTransparency: reduceTransparency)
                }
            }
            .overlay(shape.strokeBorder(VaporStyle.line2, lineWidth: 0.5))
            .shadow(color: .black.opacity(0.2), radius: 9, y: 6)
    }
}

/// Undo: accent text on a light accent fill.
private struct VaporUndoButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 12.5, weight: .semibold))
            .foregroundStyle(Color.accentColor)
            .padding(.horizontal, 10)
            .padding(.vertical, 4)
            .background(VaporStyle.accentSoft, in: .rect(cornerRadius: 9, style: .continuous))
            .opacity(configuration.isPressed ? 0.7 : 1)
    }
}

/// The 5-second ring that empties until Undo expires.
private struct VaporCountdownRing: View {
    let deadline: Date

    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 30)) { context in
            let remaining = max(deadline.timeIntervalSince(context.date), 0)
            let fraction = min(remaining / Self.window, 1)
            ZStack {
                Circle().stroke(VaporStyle.line2, lineWidth: 2.2)
                Circle()
                    .trim(from: 0, to: fraction)
                    .stroke(Color.accentColor, style: StrokeStyle(lineWidth: 2.2, lineCap: .round))
                    .rotationEffect(.degrees(-90))
            }
            .frame(width: 14, height: 14)
            .frame(width: 18, height: 18)
        }
        .accessibilityHidden(true)
    }

    private static var window: TimeInterval {
        let components = VaporController.undoWindow.components
        return TimeInterval(components.seconds) + TimeInterval(components.attoseconds) / 1e18
    }
}

#if DEBUG
#Preview("Undo window") {
    VaporCalloutView(controller: VaporPreviewData.controller(
        status: VaporStatus(kind: .deleted(count: 3, failed: 0, deadline: .now.addingTimeInterval(3.5)))))
        .background(VaporPreviewBackdrop())
}

#Preview("Undo window, one failed, light") {
    VaporCalloutView(controller: VaporPreviewData.controller(
        status: VaporStatus(kind: .deleted(count: 3, failed: 1, deadline: .now.addingTimeInterval(2)))))
        .background(VaporPreviewBackdrop())
        .preferredColorScheme(.light)
}

#Preview("Freed") {
    VaporCalloutView(controller: VaporPreviewData.controller(
        status: VaporStatus(kind: .freed(bytes: 1_840_000_000, count: 3, failed: 0))))
        .background(VaporPreviewBackdrop())
}

#Preview("Refusal") {
    VaporCalloutView(controller: VaporPreviewData.controller(refusal: .standardFolder(name: "Documents")))
        .background(VaporPreviewBackdrop())
}

#Preview("Tooltip") {
    let controller = VaporPreviewData.controller(VaporPreviewData.mixed)
    controller.isOrbHovered = true
    return VaporCalloutView(controller: controller)
        .background(VaporPreviewBackdrop())
}

#Preview("Put back") {
    VaporCalloutView(controller: VaporPreviewData.controller(status: VaporStatus(kind: .restored(count: 3))))
        .background(VaporPreviewBackdrop())
}

#Preview("Not restored") {
    VaporCalloutView(controller: VaporPreviewData.controller(status: VaporStatus(kind: .notRestored(count: 1))))
        .background(VaporPreviewBackdrop())
}
#endif
