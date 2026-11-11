import SwiftUI

/// "Hold to Delete 3 Folders". Holding fills it left to right over 0.9 s; letting go early
/// drains it. The controller owns the timing; this view only samples ``VaporHoldProgress``.
///
/// VoiceOver's activate action deletes right away, since holding isn't practical there.
struct VaporHoldButton: View {
    let controller: VaporController

    @State private var pressing = false

    var body: some View {
        let hold = controller.hold
        let reduceMotion = controller.reduceMotion
        TimelineView(.animation(paused: !hold.isAnimating(at: .now))) { context in
            let progress = hold.progress(at: context.date)
            Text(.vaporHoldToDelete(controller.folders.count))
                .font(.callout.weight(.semibold))
                .foregroundStyle(.white)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 9)
                .background {
                    GeometryReader { proxy in
                        ZStack(alignment: .leading) {
                            Color.red.opacity(0.55)
                            Color.red.frame(width: proxy.size.width * progress)
                        }
                    }
                }
                .clipShape(.rect(cornerRadius: 10, style: .continuous))
        }
        .contentShape(.rect(cornerRadius: 10, style: .continuous))
        .gesture(DragGesture(minimumDistance: 0)
            .onChanged { _ in
                guard !pressing else { return }
                pressing = true
                controller.pressHold()
            }
            .onEnded { _ in
                pressing = false
                controller.releaseHold()
            })
        .opacity(controller.isStaging ? 0.5 : 1)
        // "Delete All…" from the orb's menu nudges the button sideways to point it out.
        .keyframeAnimator(initialValue: CGFloat.zero, trigger: controller.deleteNudge?.token) { content, x in
            content.offset(x: reduceMotion ? 0 : x)
        } keyframes: { _ in
            KeyframeTrack {
                SpringKeyframe(6, duration: 0.12)
                SpringKeyframe(-5, duration: 0.12)
                SpringKeyframe(3, duration: 0.1)
                SpringKeyframe(0, duration: 0.16)
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text(.vaporHoldToDelete(controller.folders.count)))
        .accessibilityHint(Text(.vaporHoldHint))
        .accessibilityAddTraits(.isButton)
        .accessibilityAction { controller.deleteAll() }
    }
}

#if DEBUG
#Preview("Hold button") {
    VaporHoldButton(controller: VaporPreviewData.controller(VaporPreviewData.mixed, panel: true))
        .frame(width: 300)
        .padding()
}
#endif
