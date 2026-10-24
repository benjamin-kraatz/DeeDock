import SwiftUI

/// The prompt bar the tab becomes: the context chip, then the question field or the request
/// being answered, with the system's small spinner while a model works. It is the only spinner:
/// it stays in one place from the question until the last streamed word.
struct RobiPromptBar: View {
    @Bindable var model: RobiModel
    let actions: RobiActions
    @FocusState private var focused: Bool

    private var thinkingLabel: LocalizedStringResource {
        model.answerModel == .claude ? .robiThinkingClaude : .robiThinkingOnDevice
    }

    var body: some View {
        HStack(spacing: 8) {
            RobiContextChip(model: model)
            if model.phase == .prompting {
                TextField(text: $model.prompt, prompt: Text(.robiPromptPlaceholder).foregroundStyle(model.ink.opacity(0.5))) {
                    Text(.robiPromptLabel)
                }
                .textFieldStyle(.plain)
                .font(.system(size: 13))
                .foregroundStyle(model.ink)
                .focused($focused)
                .onSubmit { actions.submit(model.prompt) }
            } else {
                Text(model.request)
                    .font(.system(size: 13))
                    .foregroundStyle(model.ink.opacity(0.9))
                    .lineLimit(1)
                    .truncationMode(.tail)
                Spacer(minLength: 0)
            }
            if model.phase == .thinking && model.notice == nil {
                // The system spinner draws for its colour scheme, not a tint, so it takes the
                // tab's scheme to stay visible on a dark title bar in a light appearance.
                ProgressView()
                    .progressViewStyle(.circular)
                    .controlSize(.small)
                    .environment(\.colorScheme, model.tintIsDark ? .dark : .light)
                    .accessibilityLabel(Text(thinkingLabel))
                    .transition(.opacity)
            }
        }
        .animation(.easeInOut(duration: 0.2), value: model.phase)
        .onAppear { DispatchQueue.main.asyncAfter(deadline: .now() + 0.08) { focused = true } }
        .onChange(of: model.phase) { _, phase in if phase == .prompting { focused = true } }
        .onKeyPress(.escape) { actions.dismiss(); return .handled }
    }
}

/// What the person handed to Robi, as a small capsule at the start of the prompt bar.
struct RobiContextChip: View {
    let model: RobiModel

    var body: some View {
        HStack(spacing: 5) {
            Image(systemName: symbol).imageScale(.small)
            Text(label).lineLimit(1).truncationMode(.tail)
                .contentTransition(.opacity)
        }
        .font(.system(size: 11, weight: .semibold))
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .foregroundStyle(model.ink.opacity(0.85))
        .background(Capsule().fill(model.ink.opacity(0.10)))
        .frame(maxWidth: 190, alignment: .leading)
        .fixedSize(horizontal: true, vertical: false)
        // "Reading…" becomes the word count without a jump once the region has been read.
        .animation(.easeInOut(duration: 0.2), value: model.isReadingContext)
        .accessibilityElement(children: .combine)
    }

    private var symbol: String {
        switch model.context?.kind {
        case .selection: "text.quote"
        case .region: "viewfinder"
        case .window: "macwindow"
        case nil: "ellipsis"
        }
    }

    private var label: LocalizedStringResource {
        guard let context = model.context else { return .robiContextReading }
        switch context.kind {
        case .selection: return .robiContextSelection(context.excerpt)
        case .region: return model.isReadingContext ? .robiContextReading : .robiContextRegion(context.wordCount)
        case .window: return model.isReadingContext ? .robiContextReading : .robiContextWindow
        }
    }
}
