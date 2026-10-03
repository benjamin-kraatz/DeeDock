import AppKit
import SwiftUI

/// The stack's back button. In a volume stack it is also a drop target during a file drag: it widens
/// to name the folder it leads to, a drop copies or moves into that folder, and resting on it climbs
/// one level, the way Finder's spring-loaded folders work in reverse.
struct FolderStackBackButton: View {
    let state: FolderStackState
    let reduceMotion: Bool

    /// Only volume stacks offer the drop target; elsewhere the button stays a compact chevron.
    private var expanded: Bool { state.springsUp && (state.dragInside || state.upTargeted) }

    var body: some View {
        Button { state.back() } label: {
            HStack(spacing: 5) {
                Image(systemName: expanded ? "arrow.turn.left.up" : "chevron.left")
                    .contentTransition(.symbolEffect(.replace))
                if expanded, let parent = state.parentName {
                    Text(verbatim: parent)
                        .lineLimit(1)
                        .truncationMode(.middle)
                        .frame(maxWidth: 160)
                        .transition(.opacity.combined(with: .move(edge: .leading)))
                }
            }
            .font(.system(size: 12, weight: .semibold))
            .padding(.horizontal, expanded ? 9 : 0)
            .frame(height: 24)
            .foregroundStyle(state.upTargeted ? AnyShapeStyle(.white) : AnyShapeStyle(.primary))
            .background {
                if expanded {
                    Capsule().fill(state.upTargeted ? AnyShapeStyle(Color.accentColor) : AnyShapeStyle(.quaternary))
                }
            }
            .scaleEffect(state.upTargeted && !reduceMotion ? 1.06 : 1)
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .disabled(state.copying)
        .overlay {
            if state.springsUp { FolderStackUpTarget(state: state) }
        }
        .animation(reduceMotion ? .easeInOut(duration: 0.12) : .spring(duration: 0.3, bounce: 0.25), value: expanded)
        .animation(reduceMotion ? nil : .spring(duration: 0.25, bounce: 0.3), value: state.upTargeted)
        .help(Text(.folderStackBack))
        .accessibilityLabel(Text(.folderStackBack))
        .accessibilityValue(Text(verbatim: state.parentName ?? ""))
    }
}

/// Native drop and spring-loading destination laid over the back button. SwiftUI's drop modifiers
/// have no spring-loading, and the dwell is what lets a drag climb out of a folder it sprang into.
private struct FolderStackUpTarget: NSViewRepresentable {
    let state: FolderStackState

    func makeNSView(context: Context) -> TargetView {
        let view = TargetView()
        view.registerForDraggedTypes([.fileURL])
        return view
    }
    func updateNSView(_ view: TargetView, context: Context) { view.state = state }
    static func dismantleNSView(_ view: TargetView, coordinator: ()) { view.stop() }

    final class TargetView: NSView, NSSpringLoadingDestination {
        weak var state: FolderStackState?

        // The overlay covers the SwiftUI button, so it performs the click itself. Drag destinations
        // are found through ordinary hit testing, so it must not opt out of that.
        override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
        override func isAccessibilityElement() -> Bool { false }
        override func mouseDown(with event: NSEvent) {}
        override func mouseUp(with event: NSEvent) {
            guard let state, !state.copying, bounds.contains(convert(event.locationInWindow, from: nil)) else { return }
            state.back()
        }

        private func operation(_ info: NSDraggingInfo) -> NSDragOperation {
            guard let state, state.parentDirectory != nil else { return [] }
            return state.dropOperation(info)
        }
        private func setTargeted(_ info: NSDraggingInfo?) {
            guard let state else { return }
            let targeted = info.map { !operation($0).isEmpty } ?? false
            if state.upTargeted != targeted { state.upTargeted = targeted }
            state.dropTargetChanged(targeted ? info : nil, destination: state.parentName ?? "")
        }

        override func draggingEntered(_ sender: NSDraggingInfo) -> NSDragOperation {
            setTargeted(sender)
            return operation(sender)
        }
        override func draggingUpdated(_ sender: NSDraggingInfo) -> NSDragOperation { draggingEntered(sender) }
        override func draggingExited(_ sender: NSDraggingInfo?) { setTargeted(nil) }
        override func draggingEnded(_ sender: NSDraggingInfo) { setTargeted(nil) }
        override func prepareForDragOperation(_ sender: NSDraggingInfo) -> Bool { !operation(sender).isEmpty }
        override func performDragOperation(_ sender: NSDraggingInfo) -> Bool {
            guard let state, let parent = state.parentDirectory else { return false }
            state.upTargeted = false
            return state.receive(sender, into: parent)
        }

        func springLoadingEntered(_ info: NSDraggingInfo) -> NSSpringLoadingOptions {
            operation(info).isEmpty ? [] : .enabled
        }
        func springLoadingUpdated(_ info: NSDraggingInfo) -> NSSpringLoadingOptions { springLoadingEntered(info) }
        func springLoadingActivated(_ activated: Bool, draggingInfo: NSDraggingInfo) {
            guard activated, let state, !operation(draggingInfo).isEmpty else { return }
            state.upTargeted = false
            state.back()
        }
        func springLoadingHighlightChanged(_ info: NSDraggingInfo) {}
        func springLoadingExited(_ info: NSDraggingInfo) { setTargeted(nil) }

        func stop() {
            unregisterDraggedTypes()
            state?.upTargeted = false
            state = nil
        }
    }
}
