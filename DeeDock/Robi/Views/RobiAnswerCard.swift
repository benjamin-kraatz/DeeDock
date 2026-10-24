import SwiftUI

/// The card that drops into the window under the prompt bar: the streaming answer, a proposed
/// command, the actions that put the answer back into the app, and which model answered.
struct RobiAnswerCard: View {
    let model: RobiModel
    let actions: RobiActions

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            if let notice = model.notice {
                RobiNoticeView(notice: notice, model: model, actions: actions)
                    .transition(.opacity)
            } else {
                RobiAnswerText(model: model)
                if let proposal = model.proposal {
                    RobiProposalButton(proposal: proposal, isReady: model.phase == .answered,
                                       reduceMotion: model.reduceMotion, run: actions.runProposal)
                        .transition(model.reduceMotion ? .opacity : .scale(scale: 0.9, anchor: .leading).combined(with: .opacity))
                }
                RobiAnswerActions(model: model, actions: actions)
            }
            RobiModelFooter(model: model)
        }
        .padding(14)
        .frame(width: RobiMetrics.cardWidth, alignment: .leading)
        .background(RobiCardBackground(isDark: model.cardIsDark, reduceTransparency: model.reduceTransparency)
            .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous)))
        .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous)
            .strokeBorder(model.cardIsDark ? Color.white.opacity(0.10) : Color.black.opacity(0.08)))
        .shadow(color: .black.opacity(model.cardIsDark ? 0.36 : 0.18), radius: 16, y: 8)
        .environment(\.colorScheme, model.cardIsDark ? .dark : .light)
        // The card grows with the answer instead of jumping a line at a time, and a proposal or
        // notice settles in with the same spring as the rest of Robi.
        .animation(.easeOut(duration: model.reduceMotion ? 0.1 : 0.22), value: model.answer)
        .animation(RobiMotion.morph(model.reduceMotion), value: model.proposal)
        .animation(RobiMotion.morph(model.reduceMotion), value: model.notice)
    }
}

/// The answer as it streams in, or the waiting line before the first words arrive.
private struct RobiAnswerText: View {
    let model: RobiModel

    var body: some View {
        if model.answer.isEmpty {
            HStack(spacing: 8) {
                RobiSpinner(color: .secondary)
                Text(model.answerModel == .claude ? .robiThinkingClaude : .robiThinkingOnDevice)
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
            }
            .frame(height: 20)
            .transition(.opacity)
        } else {
            ScrollView {
                Text(model.answer)
                    .font(.system(size: 13))
                    .lineSpacing(2)
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .scrollBounceBehavior(.basedOnSize)
            .frame(maxHeight: 190)
            .fixedSize(horizontal: false, vertical: true)
            .transition(.opacity)
        }
    }
}

/// The menu command the model proposed. Nothing runs until it is clicked, and not before the
/// answer is complete.
private struct RobiProposalButton: View {
    let proposal: RobiProposal
    let isReady: Bool
    let reduceMotion: Bool
    let run: () -> Void

    var body: some View {
        Button(action: run) {
            Label { Text(.robiRunCommand(proposal.path)) } icon: { Image(systemName: "play.fill") }
                .lineLimit(1)
        }
        .buttonStyle(RobiProminentButtonStyle(reduceMotion: reduceMotion))
        .disabled(!isReady)
    }
}

/// Copy, Replace, Paste and Done, with a passing confirmation between them. The first three stay
/// disabled until the answer is complete.
private struct RobiAnswerActions: View {
    let model: RobiModel
    let actions: RobiActions

    private var toastTransition: AnyTransition {
        model.reduceMotion ? .opacity : .asymmetric(insertion: .scale(scale: 0.9).combined(with: .opacity), removal: .opacity)
    }

    var body: some View {
        HStack(spacing: 8) {
            Group {
                Button(action: actions.copy) { Text(.robiActionCopy) }
                if model.canReplace {
                    Button(action: actions.replace) { Text(.robiActionReplace) }
                }
                Button(action: actions.paste) { Text(.robiActionPaste(model.applicationName)) }
            }
            .disabled(model.phase != .answered || model.answer.isEmpty)
            Spacer(minLength: 4)
            if let toast = model.toast {
                Text(toast)
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.tail)
                    .transition(toastTransition)
            }
            Button(action: actions.dismiss) { Text(.robiActionDone) }
                .keyboardShortcut(.cancelAction)
        }
        .controlSize(.small)
        .animation(RobiMotion.feedback(model.reduceMotion), value: model.toast)
    }
}

/// Which model answered and where the context went. Transparent, not a warning.
private struct RobiModelFooter: View {
    let model: RobiModel

    var body: some View {
        Label {
            Text(model.answerModel == .claude ? .robiFooterClaude : .robiFooterOnDevice)
        } icon: {
            Image(systemName: model.answerModel == .claude ? "sparkle" : "lock.shield")
        }
        .font(.system(size: 11))
        .foregroundStyle(.secondary)
        .lineLimit(1)
        .truncationMode(.tail)
    }
}

/// What the card says when it cannot show an answer yet.
private struct RobiNoticeView: View {
    let notice: RobiNotice
    let model: RobiModel
    let actions: RobiActions
    @State private var key = ""
    @FocusState private var keyFocused: Bool
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            switch notice {
            case .claudeKeyMissing:
                Label {
                    Text(.robiKeyTitle).font(.system(size: 13, weight: .semibold))
                } icon: {
                    Image(systemName: "key.fill").foregroundStyle(.secondary)
                }
                HStack(spacing: 8) {
                    SecureField(text: $key, prompt: Text(verbatim: "sk-ant-…")) { Text(.robiKeyFieldLabel) }
                        .textFieldStyle(.roundedBorder)
                        .focused($keyFocused)
                        .onSubmit { actions.saveClaudeKey(key) }
                    Button { actions.saveClaudeKey(key) } label: { Text(.robiKeyUse) }
                        .buttonStyle(RobiProminentButtonStyle(reduceMotion: model.reduceMotion))
                        .disabled(key.trimmingCharacters(in: .whitespaces).isEmpty)
                        .keyboardShortcut(.defaultAction)
                }
                Label { Text(.robiKeyPrivacy) } icon: { Image(systemName: "lock") }
                    .font(.system(size: 11)).foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                HStack {
                    Button(action: actions.answerOnDevice) { Text(.robiAnswerOnDeviceInstead) }
                        .buttonStyle(.link)
                    Spacer()
                    Button(action: actions.dismiss) { Text(.robiActionCancel) }.keyboardShortcut(.cancelAction)
                }
            case let .onDeviceUnavailable(reason):
                RobiNoticeMessage(symbol: "apple.intelligence") { Text(reason) }
                settingsRow
            case .screenRecordingNeeded:
                RobiNoticeMessage(symbol: "rectangle.dashed.badge.record") { Text(.robiScreenRecordingNeeded) }
                settingsRow
            case let .failed(message):
                RobiNoticeMessage(symbol: "exclamationmark.circle") { Text(message) }
                HStack {
                    Spacer()
                    Button(action: actions.dismiss) { Text(.robiActionDone) }.keyboardShortcut(.cancelAction)
                }
            }
        }
        .controlSize(.small)
        // The field takes the keyboard once the card has landed, so a key can be pasted straight in.
        .onAppear { if notice == .claudeKeyMissing { DispatchQueue.main.asyncAfter(deadline: .now() + 0.12) { keyFocused = true } } }
    }

    private var settingsRow: some View {
        HStack {
            Button {
                actions.openSettings()
                openWindow.openDockSettings()
            } label: { Text(.robiOpenSettings) }
            Spacer()
            Button(action: actions.dismiss) { Text(.robiActionDone) }.keyboardShortcut(.cancelAction)
        }
    }
}

/// A notice line: a quiet symbol beside wrapped text, in the same voice as the answer.
private struct RobiNoticeMessage<Message: View>: View {
    let symbol: String
    @ViewBuilder let message: Message

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Image(systemName: symbol)
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(.secondary)
                .accessibilityHidden(true)
            message
                .font(.system(size: 13))
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}

/// The card's surface. A popover material forced active, because Robi's panel belongs to an app
/// that is not frontmost and materials would otherwise draw in their inactive grey. With Reduce
/// Transparency it is a solid colour.
struct RobiCardBackground: NSViewRepresentable {
    let isDark: Bool
    let reduceTransparency: Bool

    func makeNSView(context: Context) -> NSVisualEffectView {
        let view = NSVisualEffectView()
        view.material = .popover
        view.blendingMode = .behindWindow
        view.state = .active
        return view
    }

    func updateNSView(_ view: NSVisualEffectView, context: Context) {
        view.appearance = NSAppearance(named: isDark ? .darkAqua : .aqua)
        view.state = reduceTransparency ? .inactive : .active
        view.material = reduceTransparency ? .windowBackground : .popover
    }
}
