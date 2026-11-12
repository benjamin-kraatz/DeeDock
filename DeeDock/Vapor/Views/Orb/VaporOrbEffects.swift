import SwiftUI

/// The orb's one-shot reactions, each keyframed from an event token so it replays on every
/// event and rests at identity otherwise. All of them stand still under Reduce Motion, except
/// the refusal rim and the flash, which only change colour and opacity.
extension View {
    /// Squash when folders land (wider and shorter, then a little taller, then round), and a
    /// small dip when the panel opens.
    func vaporSquash(additionToken: UUID?, openPulse: Int, reduceMotion: Bool) -> some View {
        modifier(VaporSquashEffect(additionToken: additionToken, openPulse: openPulse, reduceMotion: reduceMotion))
    }

    /// A sideways shake when a drop is refused.
    func vaporShake(token: UUID?, reduceMotion: Bool) -> some View {
        keyframeAnimator(initialValue: CGFloat.zero, trigger: token) { content, x in
            content.offset(x: reduceMotion ? 0 : x)
        } keyframes: { _ in
            KeyframeTrack {
                CubicKeyframe(-7, duration: 0.084)
                CubicKeyframe(6, duration: 0.084)
                CubicKeyframe(-4, duration: 0.084)
                CubicKeyframe(3, duration: 0.084)
                CubicKeyframe(0, duration: 0.084)
            }
        }
    }
}

private struct VaporSquashValues {
    var x: CGFloat = 1
    var y: CGFloat = 1
}

private struct VaporSquashEffect: ViewModifier {
    let additionToken: UUID?
    let openPulse: Int
    let reduceMotion: Bool

    func body(content: Content) -> some View {
        content
            .keyframeAnimator(initialValue: VaporSquashValues(), trigger: additionToken) { content, value in
                content.scaleEffect(x: reduceMotion ? 1 : value.x, y: reduceMotion ? 1 : value.y)
            } keyframes: { _ in
                KeyframeTrack(\.x) {
                    CubicKeyframe(1.07, duration: 0.13)
                    CubicKeyframe(0.96, duration: 0.156)
                    CubicKeyframe(1.015, duration: 0.13)
                    CubicKeyframe(1, duration: 0.104)
                }
                KeyframeTrack(\.y) {
                    CubicKeyframe(0.9, duration: 0.13)
                    CubicKeyframe(1.05, duration: 0.156)
                    CubicKeyframe(0.99, duration: 0.13)
                    CubicKeyframe(1, duration: 0.104)
                }
            }
            .keyframeAnimator(initialValue: CGFloat(1), trigger: openPulse) { content, scale in
                content.scaleEffect(reduceMotion ? 1 : scale)
            } keyframes: { _ in
                KeyframeTrack {
                    CubicKeyframe(0.93, duration: 0.108)
                    CubicKeyframe(1, duration: 0.252)
                }
            }
    }
}

/// The red rim, shown for about half a second on each refusal.
struct VaporOrbRefusalFlash: View {
    let token: UUID?

    var body: some View {
        VaporOrbRefusalRim()
            .keyframeAnimator(initialValue: 0.0, trigger: token) { content, opacity in
                content.opacity(opacity)
            } keyframes: { _ in
                KeyframeTrack {
                    LinearKeyframe(1, duration: 0.05)
                    LinearKeyframe(1, duration: 0.4)
                    LinearKeyframe(0, duration: 0.15)
                }
            }
    }
}

/// The soft flash inside the glass when the orb evaporates, timed to start just after the
/// first folder lifts off. Under Reduce Motion it is shorter and fainter.
struct VaporOrbEvaporateFlash: View {
    let deletion: VaporEvent<VaporDeletion>?
    let reduceMotion: Bool

    var body: some View {
        let delay = reduceMotion ? 0 : VaporMotion.evaporateDelay(rows: deletion?.payload.folders.count ?? 0,
                                                                  fromPanel: deletion?.payload.fromPanel ?? false) + 0.12
        VaporOrbFlash()
            .keyframeAnimator(initialValue: 0.0, trigger: deletion?.token) { content, opacity in
                content.opacity(opacity)
            } keyframes: { _ in
                KeyframeTrack {
                    LinearKeyframe(0, duration: max(delay, 0.001))
                    CubicKeyframe(reduceMotion ? 0.4 : 0.85, duration: reduceMotion ? 0.075 : 0.16)
                    CubicKeyframe(0, duration: reduceMotion ? 0.225 : 0.49)
                }
            }
    }
}
