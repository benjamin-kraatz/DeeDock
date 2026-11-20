import SwiftUI

/// The footer: the noise switch, key hints, and the toast that slides over them.
struct FlixFooterView: View {
    let state: FlixPanelState
    let noiseCount: Int

    var body: some View {
        HStack(spacing: 12) {
            if noiseCount > 0 {
                Button { state.showNoise.toggle() } label: {
                    HStack(spacing: 4) {
                        if !state.showNoise { FlixSparkle(size: 10) }
                        Text(state.showNoise ? .flixNoiseShowing(noiseCount) : .flixNoiseHidden(noiseCount))
                        Text(state.showNoise ? .flixNoiseHide : .flixNoiseShow)
                            .fontWeight(.semibold)
                            .foregroundStyle(Color.accentColor)
                    }
                }
                .buttonStyle(.plain)
            }
            Spacer(minLength: 0)
            FlixKeyHint(keys: ["↩"], title: .flixHintOpen)
            if state.intelligence.canAskRobi { FlixKeyHint(keys: ["⌘", "R"], title: .flixHintAskRobi) }
            FlixKeyHint(keys: ["␣"], title: .flixHintQuickLook)
        }
        .font(.system(size: 11))
        .foregroundStyle(.tertiary)
        .padding(.horizontal, 14)
        .frame(height: FlixStyle.footerHeight)
        .overlay {
            if let toast = state.toast {
                FlixToastView(toast: toast, undo: state.performUndo)
                    .transition(state.reduceMotion ? .opacity : .move(edge: .bottom))
            }
        }
        .clipped()
        .animation(state.reduceMotion ? .easeOut(duration: 0.15) : .spring(response: 0.32, dampingFraction: 0.86),
                   value: state.toast)
    }
}

/// One key hint: keycaps and what they do.
struct FlixKeyHint: View {
    let keys: [String]
    let title: LocalizedStringResource

    var body: some View {
        HStack(spacing: 5) {
            HStack(spacing: 3) {
                ForEach(keys, id: \.self) { key in
                    Text(verbatim: key)
                        .font(.system(size: 10.5))
                        .foregroundStyle(.primary)
                        .frame(minWidth: 17, minHeight: 17)
                        .padding(.horizontal, 2)
                        .background(Color.primary.opacity(0.09), in: RoundedRectangle(cornerRadius: 4, style: .continuous))
                }
            }
            .accessibilityHidden(true)
            Text(title)
        }
        .accessibilityElement(children: .combine)
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
            Spacer(minLength: 0)
            if toast.undo != nil {
                Button(action: undo) { Text(.flixUndo).fontWeight(.semibold) }
                    .buttonStyle(.plain)
                    .foregroundStyle(Color.accentColor)
            }
        }
        .font(.system(size: 11.5))
        .padding(.leading, 14)
        .padding(.trailing, 10)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(nsColor: .windowBackgroundColor))
        .onAppear {
            NSAccessibility.post(element: NSApp as Any, notification: .announcementRequested,
                                 userInfo: [.announcement: toast.message, .priority: NSAccessibilityPriorityLevel.high.rawValue])
        }
    }
}
