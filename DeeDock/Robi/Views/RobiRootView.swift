import SwiftUI

/// Everything inside Robi's panel: the tab, and below it the suggestions or the answer card.
struct RobiRootView: View {
    let model: RobiModel
    let eyes: RobiEyes
    let actions: RobiActions

    var body: some View {
        VStack(spacing: 0) {
            if model.placement == .above { Color.clear.frame(height: RobiMetrics.shadowMargin) }
            RobiTabView(model: model, eyes: eyes, actions: actions)
            if model.phase == .prompting {
                RobiSuggestionRow(model: model, actions: actions)
                    .padding(.top, 8)
                    .transition(model.reduceMotion ? .opacity : .opacity.combined(with: .offset(y: -6)))
            }
            if model.phase.showsCard {
                RobiAnswerCard(model: model, actions: actions)
                    .padding(.top, 8)
                    .transition(model.reduceMotion ? .opacity : .scale(scale: 0.92, anchor: .top).combined(with: .opacity))
            }
            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .animation(RobiMotion.morph(model.reduceMotion), value: model.phase)
        .animation(.easeInOut(duration: 0.35), value: model.tintIsDark)
    }
}

/// The tab growing out of the window: the face, and the hint or prompt bar beside it.
struct RobiTabView: View {
    let model: RobiModel
    let eyes: RobiEyes
    let actions: RobiActions

    private var inverted: Bool { model.placement == .inside }
    private var centred: Bool { model.phase == .idle || model.phase == .awake }
    private var selecting: Bool { model.phase == .selecting }
    /// Pulled away from the edge by a Shift-drag; the controller allows it only hanging inside.
    private var isGooey: Bool { model.goo != .zero && inverted }

    var body: some View {
        ZStack(alignment: .top) {
            if isGooey {
                RobiGooSurface(tint: model.tint, rim: model.rim, goo: model.goo)
            } else {
                RobiTabSurface(tint: model.tint, rim: model.rim, inverted: inverted)
            }
            HStack(spacing: selecting ? 8 : 10) {
                RobiFaceButton(model: model, eyes: eyes, actions: actions)
                if selecting {
                    Text(.robiSelectingHint)
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(model.ink.opacity(0.72))
                        .lineLimit(1)
                        .allowsTightening(true)
                        // The 340 pt tab holds the English hint at full size; German is about 6 %
                        // wider and tightens rather than truncating.
                        .minimumScaleFactor(0.9)
                        .transition(.opacity)
                }
                if model.phase.isBar {
                    RobiPromptBar(model: model, actions: actions)
                        .transition(.opacity)
                }
            }
            .padding(.leading, RobiMetrics.flare + 7)
            .padding(.trailing, RobiMetrics.flare + (selecting ? 5 : 7))
            .frame(maxWidth: .infinity, alignment: centred ? .center : .leading)
            .frame(height: RobiMetrics.tabHeight)
            .offset(y: inverted ? -1 : 2)
            // The face rides in the goo's bulb.
            .offset(x: isGooey ? model.goo.width : 0, y: isGooey ? model.goo.height : 0)
        }
        // The goo's neck adds to the tab's height; the panel already has room for it.
        .frame(width: model.tabWidth, height: RobiMetrics.tabHeight + (isGooey ? model.goo.height : 0), alignment: .top)
        .scaleEffect(x: 1, y: model.isPresent ? 1 : 0.02, anchor: inverted ? .top : .bottom)
        .opacity(model.isPresent ? 1 : 0)
        .animation(RobiMotion.presence(model.reduceMotion), value: model.isPresent)
    }
}

/// The face: a button to VoiceOver, and to the pointer a handle that clicks or drags the tab
/// (`RobiFaceHandle`). A view of its own so streaming answer text, which decides whether the
/// eyes wander, redraws only the face and not the whole tab.
private struct RobiFaceButton: View {
    let model: RobiModel
    let eyes: RobiEyes
    let actions: RobiActions

    var body: some View {
        RobiFaceView(eyes: eyes, phase: model.phase, compact: model.phase.isBar,
                     isWaiting: model.answer.isEmpty && model.notice == nil, badge: model.parkedBadge,
                     reduceMotion: model.reduceMotion)
            .modifier(RobiFaceHandle(report: actions.faceGesture))
            .accessibilityElement(children: .ignore)
            .accessibilityAddTraits(.isButton)
            .accessibilityLabel(Text(.robiName))
            .accessibilityValue(badgeDescription)
            .accessibilityHint(Text(model.phase.isEngaged ? .robiFaceHintDismiss : .robiFaceHintAsk))
            .accessibilityAction { actions.tapFace() }
    }
}

private extension RobiFaceButton {
    var badgeDescription: Text {
        guard let badge = model.parkedBadge else { return Text(verbatim: "") }
        return Text(badge.isWorking ? .robiParkedWorking(badge.applicationName) : .robiParkedReady(badge.applicationName))
    }
}

/// The tab's tinted body, its rim, and a soft shadow.
///
/// The shadow is masked to the tab's side of the window edge: it may spread beside the tab and
/// away from the window, never across the edge, so the title bar under the tab stays as light as
/// the rest of it. Hanging inside, the shadow falls onto the window content instead, like a notch.
private struct RobiTabSurface: View {
    let tint: Color
    let rim: Color
    let inverted: Bool

    var body: some View {
        ZStack {
            RobiTabShape(inverted: inverted)
                .fill(tint)
                .shadow(color: .black.opacity(0.16), radius: 4, y: inverted ? 2 : -1)
                .mask {
                    Rectangle()
                        .padding(.horizontal, -RobiMetrics.sideMargin)
                        .padding(inverted ? .bottom : .top, -RobiMetrics.shadowMargin)
                }
            RobiTabShape(inverted: inverted, closed: false)
                .stroke(rim, lineWidth: 1)
        }
        // A new window's colour fades in rather than snapping, as in the mockup.
        .animation(.easeInOut(duration: 0.35), value: tint)
    }
}

/// Robi's springs, from the spike's lab. Reduce Motion swaps every one for a short fade.
enum RobiMotion {
    static func morph(_ reduceMotion: Bool) -> Animation {
        reduceMotion ? .easeInOut(duration: 0.15) : .spring(response: 0.42, dampingFraction: 0.8)
    }

    /// Retracting into one window and emerging from the next: a little bouncier than the morph.
    static func presence(_ reduceMotion: Bool) -> Animation {
        reduceMotion ? .easeInOut(duration: 0.15) : .spring(response: 0.42, dampingFraction: 0.72)
    }

    /// Hover and press feedback on pills and buttons.
    static func feedback(_ reduceMotion: Bool) -> Animation {
        reduceMotion ? .easeInOut(duration: 0.1) : .easeOut(duration: 0.15)
    }

    /// One suggestion pill arriving after the one before it. Reduce Motion drops the stagger.
    static func stagger(_ index: Int, reduceMotion: Bool) -> Animation {
        reduceMotion ? .easeInOut(duration: 0.15)
                     : .spring(response: 0.38, dampingFraction: 0.74).delay(0.05 + 0.045 * Double(index))
    }
}
