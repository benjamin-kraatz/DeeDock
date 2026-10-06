import SwiftUI

/// A small screen showing where the macOS Dock sits relative to DOKK's dock.
///
/// Untucked, the macOS Dock spans the bottom and DOKK sits above it. Tucked away, it shrinks
/// to a faint sliver on its side. Both bars are single views whose alignment changes, so the
/// change animates as one movement. Decorative: the status text beside it says the same thing.
struct SystemDockTuckDiagram: View {
    /// Where DOKK put the macOS Dock, or nil when it is in the person's own position.
    let tucked: SystemDockOrientation?
    /// DOKK's dock on the main display.
    let dokkEdge: DockEdge
    var reduceMotionOverride: Bool? = nil
    @Environment(\.accessibilityReduceMotion) private var systemReduceMotion

    private var reduceMotion: Bool { reduceMotionOverride ?? systemReduceMotion }
    private var screen: RoundedRectangle { RoundedRectangle(cornerRadius: 7, style: .continuous) }

    var body: some View {
        ZStack {
            screen.fill(.background.tertiary)
            systemDock
            dokkDock
        }
        .clipShape(screen)
        .overlay(screen.strokeBorder(.separator, lineWidth: 1))
        .frame(width: 112, height: 72)
        .animation(reduceMotion ? .easeInOut(duration: 0.1) : .spring(duration: 0.55, bounce: 0.22), value: tucked)
        .animation(reduceMotion ? nil : .smooth(duration: 0.3), value: dokkEdge)
        .accessibilityHidden(true)
    }

    private var systemDock: some View {
        Capsule()
            .fill(.secondary)
            .frame(width: tucked == nil ? 58 : 3, height: tucked == nil ? 7 : 22)
            .opacity(tucked == nil ? 0.8 : 0.4)
            .padding(tucked == nil ? 4 : 2)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: systemDockAlignment)
    }

    private var systemDockAlignment: Alignment {
        switch tucked {
        case nil: .bottom
        case .left: .leading
        case .right: .trailing
        }
    }

    private var dokkDock: some View {
        RoundedRectangle(cornerRadius: 2.5, style: .continuous)
            .fill(.tint)
            .frame(width: dokkEdge.isVertical ? 6 : 46, height: dokkEdge.isVertical ? 34 : 6)
            .padding(dokkInsets)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: dokkAlignment)
    }

    private var dokkAlignment: Alignment {
        switch dokkEdge {
        case .bottom: .bottom
        case .top: .top
        case .left: .leading
        case .right: .trailing
        }
    }

    /// DOKK's bottom dock rests above an untucked macOS Dock, as `visibleFrame` places it.
    private var dokkInsets: EdgeInsets {
        let resting: CGFloat = 5
        let raised = dokkEdge == .bottom && tucked == nil ? 15 : resting
        return EdgeInsets(top: resting, leading: resting, bottom: raised, trailing: resting)
    }
}

#if DEBUG
#Preview("Diagram states") {
    HStack(spacing: 16) {
        SystemDockTuckDiagram(tucked: nil, dokkEdge: .bottom)
        SystemDockTuckDiagram(tucked: .left, dokkEdge: .bottom)
        SystemDockTuckDiagram(tucked: .right, dokkEdge: .left)
    }
    .padding(24)
}

#Preview("Diagram — interactive") {
    @Previewable @State var tucked: SystemDockOrientation? = nil
    VStack(spacing: 16) {
        SystemDockTuckDiagram(tucked: tucked, dokkEdge: .bottom)
        Button {
            tucked = tucked == nil ? .left : nil
        } label: {
            Text(tucked == nil ? LocalizedStringResource.systemDockTuckAction : .systemDockRestoreAction)
        }
    }
    .padding(24)
}
#endif
