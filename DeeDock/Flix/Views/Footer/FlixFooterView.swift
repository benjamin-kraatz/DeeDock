import SwiftUI

/// The footer: the noise switch, key hints, and the toast that slides over them.
///
/// The key hints give way to the noise switch when both do not fit (long German labels): first
/// Ask Robi's hint goes, then Quick Look's. The toast slides up from the bottom edge and back down
/// (``FlixMotion/toast``); with Reduce Motion it crossfades.
struct FlixFooterView: View {
    let state: FlixPanelState
    let noiseCount: Int

    var body: some View {
        HStack(spacing: 12) {
            if noiseCount > 0 {
                FlixNoiseSwitch(count: noiseCount, showing: state.showNoise) { state.showNoise.toggle() }
                    .layoutPriority(1)
            }
            Spacer(minLength: 0)
            ViewThatFits(in: .horizontal) {
                hints(robi: state.intelligence.canAskRobi, quickLook: true)
                hints(robi: false, quickLook: true)
                hints(robi: false, quickLook: false)
            }
        }
        .font(.system(size: 11))
        .foregroundStyle(FlixStyle.faint)
        .padding(.horizontal, 14)
        .frame(height: FlixStyle.footerHeight)
        .overlay {
            if let toast = state.toast {
                FlixToastView(toast: toast, undo: state.performUndo)
                    .transition(state.reduceMotion ? .opacity : .move(edge: .bottom))
                    .id(toast.id)
            }
        }
        .clipped()
        .animation(FlixMotion.resolved(FlixMotion.toast, reduceMotion: state.reduceMotion), value: state.toast)
    }

    private func hints(robi: Bool, quickLook: Bool) -> some View {
        HStack(spacing: 12) {
            FlixKeyHint(keys: ["return"], title: .flixHintOpen)
            if robi { FlixKeyHint(keys: ["command", "R"], title: .flixHintAskRobi) }
            if quickLook { FlixKeyHint(keys: ["space"], title: .flixHintQuickLook) }
        }
        .fixedSize()
    }
}

/// "✦ 3 hidden as noise · Show" and its opposite.
private struct FlixNoiseSwitch: View {
    let count: Int
    let showing: Bool
    let action: () -> Void
    @State private var hovered = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 4) {
                if !showing { FlixSparkle(size: 10) }
                Text(showing ? .flixNoiseShowing(count) : .flixNoiseHidden(count))
                    .foregroundStyle(hovered ? Color.primary : FlixStyle.faint)
                    .lineLimit(1)
                    .truncationMode(.middle)
                Text(showing ? .flixNoiseHide : .flixNoiseShow)
                    .fontWeight(.semibold)
                    .foregroundStyle(Color.accentColor)
                    .lineLimit(1)
                    .fixedSize()
            }
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .onHover { hovered = $0 }
        .animation(FlixMotion.hover, value: hovered)
    }
}

/// One key hint: keycaps and what they do. Keys are SF Symbol names (`return`, `command`, `space`)
/// or a letter.
struct FlixKeyHint: View {
    let keys: [String]
    let title: LocalizedStringResource

    var body: some View {
        HStack(spacing: 5) {
            HStack(spacing: 3) {
                ForEach(keys, id: \.self) { key in
                    FlixKeycap(key: key)
                }
            }
            .accessibilityHidden(true)
            Text(title).lineLimit(1)
        }
        .accessibilityElement(children: .combine)
    }
}

/// A 17-point keycap with a hairline rim and a one-point lip, like the mockup's.
private struct FlixKeycap: View {
    let key: String

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: 4, style: .continuous)
        Group {
            if key.count == 1 {
                Text(verbatim: key).font(.system(size: 10.5, weight: .medium))
            } else {
                Image(systemName: key).font(.system(size: 9, weight: .semibold))
            }
        }
        .foregroundStyle(.primary)
        .frame(minWidth: 17, minHeight: 17)
        .padding(.horizontal, key.count == 1 ? 2 : 1)
        .background(FlixStyle.key, in: shape)
        .overlay(shape.strokeBorder(FlixStyle.outline, lineWidth: 0.5))
        .shadow(color: Color.primary.opacity(0.15), radius: 0, y: 1)
    }
}

/// The footer toast with an optional Undo. Announced to VoiceOver as it appears.
struct FlixToastView: View {
    let toast: FlixToast
    let undo: () -> Void

    var body: some View {
        HStack(spacing: 8) {
            Text(verbatim: toast.message)
                .lineLimit(1)
                .truncationMode(.middle)
                .foregroundStyle(.primary)
                .help(Text(verbatim: toast.message))
            Spacer(minLength: 0)
            if toast.undo != nil {
                Button(action: undo) { Text(.flixUndo).fontWeight(.semibold) }
                    .buttonStyle(FlixToastButtonStyle())
            }
        }
        .font(.system(size: 11.5))
        .padding(.leading, 14)
        .padding(.trailing, 6)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(FlixStyle.surface)
        .onAppear {
            NSAccessibility.post(element: NSApp as Any, notification: .announcementRequested,
                                 userInfo: [.announcement: toast.message, .priority: NSAccessibilityPriorityLevel.high.rawValue])
        }
    }
}

/// The toast's accent text button, with a soft accent pill on hover.
private struct FlixToastButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        FlixHover { hovered in
            configuration.label
                .font(.system(size: 11))
                .foregroundStyle(Color.accentColor)
                .padding(.horizontal, 8)
                .frame(height: 20)
                .background(hovered ? FlixStyle.accentSoft : .clear, in: RoundedRectangle(cornerRadius: 6, style: .continuous))
                .opacity(configuration.isPressed ? 0.6 : 1)
                .contentShape(.rect)
                .fixedSize()
        }
    }
}

#if DEBUG
#Preview("Footer") {
    VStack(spacing: 0) {
        FlixFooterView(state: FlixPreviewData.panelState(withIntelligence: true), noiseCount: 3)
        FlixHairline()
        FlixFooterView(state: FlixPreviewData.panelState(), noiseCount: 0)
        FlixHairline()
        FlixFooterView(state: FlixPreviewData.panelState(.newerVersionQuestion), noiseCount: 3)
    }
    .frame(width: 516)
}

#Preview("Footer, German") {
    FlixFooterView(state: FlixPreviewData.panelState(withIntelligence: true), noiseCount: 12)
        .frame(width: 516)
        .environment(\.locale, Locale(identifier: "de"))
}
#endif
