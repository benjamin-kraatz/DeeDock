import SwiftUI

/// The card that drops into the window under the prompt bar: the streaming answer, the steps the
/// model proposed, the actions that put the answer back into the app, and which model answered.
struct RobiAnswerCard: View {
    let model: RobiModel
    let actions: RobiActions
    /// Lives as long as the card, so an answer that is briefly replaced by a notice keeps its place.
    @State private var pacer = RobiTextPacer()

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            if let notice = model.notice {
                RobiNoticeView(notice: notice, model: model, actions: actions)
                    .transition(.opacity)
            } else {
                RobiAnswerText(model: model, pacer: pacer, point: actions.point)
                if let proposal = model.proposal, !proposal.steps.isEmpty {
                    RobiProposalView(proposal: proposal, runState: model.runState, isReady: model.phase == .answered,
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
        // The first words fade in over the waiting line; `RobiAnswerScroll` animates the growth
        // after that. A proposal or notice settles in with the same spring as the rest of Robi.
        // Keyed on the revealed text, not `model.answer`, which fills a moment earlier.
        .animation(.easeOut(duration: model.reduceMotion ? 0.1 : 0.22), value: pacer.hasText)
        .animation(RobiMotion.morph(model.reduceMotion), value: model.proposal)
        .animation(RobiMotion.morph(model.reduceMotion), value: model.notice)
        .animation(.easeOut(duration: model.reduceMotion ? 0.1 : 0.22), value: model.isStopped)
    }
}

/// The answer as it streams in, or the waiting line before the first words arrive. The spinner
/// for both is in the prompt bar. A stopped answer keeps what arrived and says it was stopped.
///
/// Has the pacer follow the answer's readable text, with its Markdown syntax taken out, and shows
/// what the pacer has revealed, formatted, with the answer's references as links. The waiting line
/// stays until the first words are revealed, so it does not give way to an empty line during the
/// pacer's initial hold.
private struct RobiAnswerText: View {
    let model: RobiModel
    let pacer: RobiTextPacer
    let point: (Int) -> Void

    var body: some View {
        let markdown = model.formattedAnswer
        // A stack rather than bare content, so the modifiers below apply once and not to each child.
        VStack(alignment: .leading, spacing: 10) {
            if !pacer.hasText {
                Group {
                    if model.isStopped && model.answer.isEmpty {
                        RobiStoppedLabel()
                    } else {
                        Text(model.answerModel == .claude ? .robiThinkingClaude : .robiThinkingOnDevice)
                            .font(.system(size: 12))
                            .foregroundStyle(.secondary)
                    }
                }
                .frame(height: 20)
                .transition(.opacity)
            } else {
                RobiAnswerScroll(pacer: pacer, markdown: markdown, maxHeight: maxHeight, reduceMotion: model.reduceMotion, point: point)
                    .transition(.opacity)
                if model.isStopped {
                    RobiStoppedLabel()
                        .transition(.opacity)
                }
            }
        }
        .onAppear {
            pacer.follow { [model] in
                RobiTextPacer.Input(target: model.formattedAnswer.text, isFinished: model.phase == .answered || model.isStopped,
                                    reduceMotion: model.reduceMotion)
            }
        }
        .onDisappear { pacer.stop() }
    }

    /// The card's height is fixed (`RobiMetrics.cardHeight`, 320), so a proposal takes its room
    /// from the answer, which is one short sentence then anyway.
    ///
    /// Of the 320, the padding (28), the three gaps (30), the actions row (about 20) and the footer
    /// (about 14) are spoken for, leaving 228 for the answer and the proposal together; 218 keeps
    /// ten in hand for the rows' font metrics. Without a proposal the mockup's 190 stands, and a
    /// single step's button fits in the same budget.
    private var maxHeight: CGFloat {
        guard let count = model.proposal?.steps.count, count > 0 else { return 190 }
        return 218 - RobiProposalView.height(stepCount: count)
    }
}

/// Says the person stopped the answer, so a cut-off sentence reads as stopped, not broken.
private struct RobiStoppedLabel: View {
    var body: some View {
        Label { Text(.robiAnswerStopped) } icon: { Image(systemName: "stop.circle") }
            .font(.system(size: 11))
            .foregroundStyle(.secondary)
    }
}

/// The revealed answer, formatted, growing with the stream up to `maxHeight` and scrolling beyond it.
///
/// The height comes from measuring the text, not from the scroll view's ideal size. Each growth
/// step animates, and during that animation the text is already taller than its frame, so a
/// scroll view sized by its content flashed its scroller on every streamed chunk. The scroller is
/// allowed only once the text is taller than `maxHeight`. A stream only adds text, so that
/// happens at most once per answer and the scroller does not come and go.
///
/// This is the only view that reads `pacer.text`, so the pacer's ticks redraw nothing else. The
/// fading words differ only in colour, so they never change the measured height. Bold words are
/// wider, but a style applies from a run's first revealed character and never changes afterwards.
private struct RobiAnswerScroll: View {
    let pacer: RobiTextPacer
    /// The formatted answer the pacer's text is a prefix of: its blocks, styles and references.
    let markdown: RobiMarkdown
    let maxHeight: CGFloat
    let reduceMotion: Bool
    let point: (Int) -> Void
    /// Starts at zero for each answer: the view is rebuilt whenever the revealed text empties.
    @State private var textHeight: CGFloat = 0

    var body: some View {
        ScrollView {
            RobiMarkdownView(markdown: markdown, text: RobiAnswerStyling.styled(pacer.text, markdown: markdown))
                .font(.system(size: 13))
                .lineSpacing(2)
                .textSelection(.enabled)
                .frame(maxWidth: .infinity, alignment: .leading)
                .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { height in
                    // Animated here rather than on the text, so the card around the scroll view
                    // grows in the same transaction as its frame.
                    withAnimation(.easeOut(duration: reduceMotion ? 0.1 : 0.22)) { textHeight = height }
                }
                .help(markdown.references.isEmpty ? Text(verbatim: "") : Text(.robiReferenceHelp))
        }
        // `.never`, unlike `.hidden`, also holds when scroll bars are set to always show.
        .scrollIndicators(textHeight > maxHeight ? .automatic : .never)
        .scrollBounceBehavior(.basedOnSize)
        .frame(height: min(textHeight, maxHeight))
        // A reference's link spotlights its landmark on the window and never opens anything. Only
        // web and mail links, which the parser alone turns into links, open in their app.
        .environment(\.openURL, OpenURLAction { url in
            if let landmark = RobiReferenceLink.landmark(from: url) {
                point(landmark)
                return .handled
            }
            return ["http", "https", "mailto"].contains(url.scheme?.lowercased() ?? "") ? .systemAction : .discarded
        })
    }
}

/// Copy, Replace, Paste and Done, with a passing confirmation between them. The first three stay
/// disabled until the answer is complete or stopped. While it streams, Stop takes Done's place
/// and its Esc key, so Esc stops first and closes second.
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
            if model.phase == .thinking {
                Button(action: actions.stop) {
                    Label { Text(.robiActionStop) } icon: { Image(systemName: "stop.fill") }
                }
                .keyboardShortcut(.cancelAction)
            } else {
                Button(action: actions.dismiss) { Text(.robiActionDone) }
                    .keyboardShortcut(.cancelAction)
            }
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
            Text(text)
        } icon: {
            Image(systemName: model.answerModel == .claude ? "sparkle" : "lock.shield")
        }
        .font(.system(size: 11))
        .foregroundStyle(.secondary)
        .lineLimit(1)
        .truncationMode(.tail)
    }

    private var text: LocalizedStringResource {
        guard model.answerModel == .claude else { return .robiFooterOnDevice }
        return switch model.claudeModel {
        case .haiku: .robiFooterClaudeHaiku
        case .sonnet: .robiFooterClaudeSonnet
        case .opus: .robiFooterClaudeOpus
        }
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

#if DEBUG
/// Replays a fixed, bursty stream into a card, the way models deliver text: uneven chunks after
/// uneven gaps, then a pause and the same answer again. The pacer should turn it into an even flow.
private struct RobiStreamingPreview: View {
    @State private var model: RobiModel

    init(reduceMotion: Bool = false) {
        _model = State(initialValue: RobiPreviewData.model(.thinking, dark: true, context: RobiPreviewData.region,
                                                           model: .claude, reduceMotion: reduceMotion))
    }

    /// Characters per chunk and the wait before it, in seconds, repeated over the answer.
    private static let bursts: [(size: Int, wait: Double)] = [
        (4, 0.05), (26, 0.32), (7, 0.06), (48, 0.42), (12, 0.10), (3, 0.04), (36, 0.28),
    ]

    var body: some View {
        RobiAnswerCard(model: model, actions: RobiActions())
            .padding(24)
            .frame(width: RobiMetrics.cardWidth + 48, height: 360, alignment: .top)
            .background(Color(red: 0.12, green: 0.13, blue: 0.16))
            .task { await replay() }
    }

    private func replay() async {
        let answer = Array(RobiPreviewData.longAnswer)
        while !Task.isCancelled {
            model.answer = ""
            model.phase = .thinking
            try? await Task.sleep(for: .seconds(0.6))
            var count = 0
            var burst = 0
            while count < answer.count, !Task.isCancelled {
                let next = Self.bursts[burst % Self.bursts.count]
                try? await Task.sleep(for: .seconds(next.wait))
                count = min(count + next.size, answer.count)
                model.answer = String(answer[..<count])
                burst += 1
            }
            model.phase = .answered
            try? await Task.sleep(for: .seconds(2.5))
        }
    }
}

#Preview("Streaming in bursts, paced") { RobiStreamingPreview() }
#Preview("Streaming in bursts, Reduce Motion") { RobiStreamingPreview(reduceMotion: true) }
#endif
