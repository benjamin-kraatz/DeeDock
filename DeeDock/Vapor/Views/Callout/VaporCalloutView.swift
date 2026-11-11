import SwiftUI

/// The capsule above the orb: a refusal, the delete status with countdown and Undo, "Drop to
/// add", or the hover tooltip. ``VaporController/callout`` decides which.
struct VaporCalloutView: View {
    let controller: VaporController

    var body: some View {
        if let callout = controller.callout {
            VaporCalloutContent(callout: callout, reduceTransparency: controller.reduceTransparency,
                                undo: { controller.undo() })
                .fixedSize()
                .padding(4)
        }
    }
}

private struct VaporCalloutContent: View {
    let callout: VaporCallout
    let reduceTransparency: Bool
    let undo: () -> Void

    var body: some View {
        HStack(spacing: 10) {
            switch callout {
            case .refusal(let refusal):
                Image(systemName: "nosign")
                    .foregroundStyle(.red)
                    .accessibilityHidden(true)
                Text(VaporCopy.refusal(refusal))
            case .status(let status):
                if case .deleted(_, _, let deadline) = status.kind {
                    VaporCountdownRing(deadline: deadline)
                }
                Text(verbatim: VaporCopy.status(status.kind))
                if case .deleted = status.kind {
                    Button(.vaporUndo, action: undo)
                        .buttonStyle(.borderless)
                        .font(.callout.weight(.semibold))
                }
            case .dropToAdd:
                Text(.vaporTooltipDropToAdd)
            case .tooltip(let totals):
                Text(verbatim: VaporCopy.summary(totals))
                    .monospacedDigit()
            }
        }
        .font(.callout)
        .lineLimit(1)
        .padding(.horizontal, 12)
        .padding(.vertical, 7)
        .vaporGlass(in: Capsule(), reduceTransparency: reduceTransparency)
        .accessibilityElement(children: .combine)
    }
}

/// The 5-second ring that empties until Undo expires.
private struct VaporCountdownRing: View {
    let deadline: Date

    var body: some View {
        TimelineView(.animation) { context in
            let remaining = max(deadline.timeIntervalSince(context.date), 0)
            let fraction = remaining / VaporCountdownRing.window
            ZStack {
                Circle().stroke(Color.secondary.opacity(0.25), lineWidth: 2)
                Circle()
                    .trim(from: 0, to: fraction)
                    .stroke(Color.accentColor, style: StrokeStyle(lineWidth: 2, lineCap: .round))
                    .rotationEffect(.degrees(-90))
            }
            .frame(width: 14, height: 14)
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
        status: VaporStatus(kind: .deleted(count: 3, failed: 1, deadline: .now.addingTimeInterval(3.5)))))
}

#Preview("Freed") {
    VaporCalloutView(controller: VaporPreviewData.controller(
        status: VaporStatus(kind: .freed(bytes: 1_840_000_000, count: 3, failed: 0))))
}

#Preview("Refusal") {
    VaporCalloutView(controller: VaporPreviewData.controller(refusal: .standardFolder(name: "Documents")))
}

#Preview("Not restored") {
    VaporCalloutView(controller: VaporPreviewData.controller(status: VaporStatus(kind: .notRestored(count: 1))))
}
#endif
