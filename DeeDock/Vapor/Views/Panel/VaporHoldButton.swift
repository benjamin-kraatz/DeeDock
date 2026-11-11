import SwiftUI

/// "Hold to Delete 3 Folders". Holding fills it left to right over 0.9 s; letting go early
/// drains it. The controller owns the timing; this view only samples ``VaporHoldProgress``.
///
/// The timeline runs only while the fill changes: a task wakes the view when a hold or drain
/// ends, so the paused state is re-read and an idle button draws nothing.
///
/// VoiceOver's activate action deletes right away, since holding isn't practical there.
struct VaporHoldButton: View {
    let controller: VaporController
    /// The folder count on the label; the panel passes its frozen list while rows fly out.
    let count: Int

    @State private var pressing = false
    @State private var hovered = false
    /// Bumped when the fill stops changing, so the timeline's paused state is re-evaluated.
    @State private var settledTick = 0

    var body: some View {
        let hold = controller.hold
        let reduceMotion = controller.reduceMotion
        let enabled = count > 0 && !controller.isStaging
        let shape = RoundedRectangle(cornerRadius: 12, style: .continuous)
        // Reading the tick makes the paused state below re-evaluate when the fill settles.
        let _ = settledTick
        TimelineView(.animation(paused: !hold.isAnimating(at: .now))) { context in
            let progress = hold.progress(at: context.date)
            Text(.vaporHoldToDelete(count))
                .font(.system(size: 13.5, weight: .semibold))
                .foregroundStyle(.white)
                .frame(maxWidth: .infinity)
                .frame(height: 40)
                .background {
                    ZStack(alignment: .leading) {
                        VaporStyle.danger
                        GeometryReader { proxy in
                            Color.white.opacity(0.28)
                                .frame(width: proxy.size.width * progress)
                        }
                    }
                }
                .overlay(alignment: .top) {
                    // The glossy top edge from the mockup.
                    shape.strokeBorder(LinearGradient(colors: [.white.opacity(0.25), .clear], startPoint: .top, endPoint: .center),
                                       lineWidth: 1)
                }
                .clipShape(shape)
        }
        .brightness(hovered && enabled ? 0.04 : 0)
        .scaleEffect(pressing && !reduceMotion ? 0.985 : 1)
        .shadow(color: VaporStyle.danger.opacity(enabled ? 0.35 : 0), radius: 9, y: 6)
        .opacity(enabled ? 1 : 0.35)
        .contentShape(shape)
        .onHover { hovered = $0 }
        .gesture(DragGesture(minimumDistance: 0)
            .onChanged { _ in
                guard !pressing, enabled else { return }
                pressing = true
                controller.pressHold()
            }
            .onEnded { _ in
                guard pressing else { return }
                pressing = false
                controller.releaseHold()
            })
        .animation(.easeOut(duration: 0.12), value: pressing)
        .task(id: hold) {
            let remaining = hold.remainingAnimation(at: .now)
            guard remaining > 0 else { return }
            try? await Task.sleep(for: .seconds(remaining + 0.02))
            settledTick &+= 1
        }
        // "Delete All…" from the orb's menu nudges the button to point it out.
        .keyframeAnimator(initialValue: CGFloat(1), trigger: controller.deleteNudge?.token) { content, scale in
            content.scaleEffect(reduceMotion ? 1 : scale)
        } keyframes: { _ in
            KeyframeTrack {
                CubicKeyframe(1.04, duration: 0.15)
                CubicKeyframe(0.98, duration: 0.15)
                CubicKeyframe(1, duration: 0.2)
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text(.vaporHoldToDelete(count)))
        .accessibilityHint(Text(.vaporHoldHint))
        .accessibilityAddTraits(.isButton)
        .accessibilityAction { controller.deleteAll() }
    }
}

#if DEBUG
#Preview("Hold button, half way") {
    VaporHoldButton(controller: VaporPreviewData.controller(VaporPreviewData.mixed, panel: true, hold: .frozen(at: 0.5)),
                    count: VaporPreviewData.mixed.count)
        .frame(width: 330)
        .padding()
}
#endif
