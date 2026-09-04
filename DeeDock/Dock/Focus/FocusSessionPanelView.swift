import SwiftUI

@MainActor @Observable
final class FocusSessionPanelChrome {
    var value = DockPopoverChrome(edge: .bottom, attachment: 180)
}

/// Timer controls and an explicit handoff to the existing Session Capsule creation flow.
struct FocusSessionPanelView: View {
    let controller: FocusSessionController
    let chrome: FocusSessionPanelChrome
    let saveCapsule: () -> Void
    let close: () -> Void
    var forceOpaqueBackground = false
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency

    var body: some View {
        VStack(spacing: 18) {
            if let session = controller.session {
                Text(verbatim: session.modeName).font(.title2.bold()).lineLimit(2)
                if session.phase == .running {
                    TimelineView(.periodic(from: .now, by: 1)) { context in time(session, date: context.date) }
                } else { time(session, date: .now) }
                if session.phase == .completed {
                    Text(.focusFinishedHelp).multilineTextAlignment(.center)
                    Button(.focusSaveCapsule, systemImage: "square.stack.3d.up") { saveCapsule() }
                    Button(.focusDismiss) { controller.dismiss(); close() }
                } else {
                    HStack {
                        if session.phase == .running { Button(.focusPause) { controller.pause() } }
                        else { Button(.focusResume) { controller.resume() } }
                        Button(.focusExtend) { controller.extend() }.disabled(session.duration > 86100)
                        Button(.focusFinish) { controller.finish() }
                    }
                }
                if let error = controller.error { Text(verbatim: error).foregroundStyle(.red) }
            }
        }
        .padding(24).frame(maxWidth: .infinity, maxHeight: .infinity)
        .dockPopoverChrome(chrome.value, opaque: reduceTransparency || forceOpaqueBackground)
    }

    private func time(_ session: FocusSession, date: Date) -> some View {
        VStack {
            Text(verbatim: session.timeLabel(at: date)).font(.system(size: 46, weight: .light)).monospacedDigit()
            Text(session.phase == .completed ? .focusCompleted : session.phase == .paused ? .focusPaused : .focusRunning)
                .foregroundStyle(.secondary)
        }
    }
}

#if DEBUG
private func focusPreviewController(completed: Bool) -> FocusSessionController {
    let session = FocusSession(id: UUID(uuidString: "11111111-1111-1111-1111-111111111111")!,
                               modeID: UUID(uuidString: "22222222-2222-2222-2222-222222222222")!,
                               modeName: "Writing", duration: 1500,
                               remainingWhenPaused: completed ? 0 : 1020, deadline: nil,
                               phase: completed ? .completed : .paused)
    return FocusSessionController(defaults: UserDefaults(suiteName: "FocusPanelPreview")!,
                                  document: FocusSessionsDocument(session: session))
}

#Preview("Paused focus") {
    FocusSessionPanelView(controller: focusPreviewController(completed: false),
                          chrome: FocusSessionPanelChrome(), saveCapsule: {}, close: {})
        .frame(width: 400, height: 290).padding()
}
#Preview("Completed focus, opaque") {
    FocusSessionPanelView(controller: focusPreviewController(completed: true),
                          chrome: FocusSessionPanelChrome(), saveCapsule: {}, close: {}, forceOpaqueBackground: true)
        .frame(width: 400, height: 290).padding().preferredColorScheme(.dark)
}
#endif
