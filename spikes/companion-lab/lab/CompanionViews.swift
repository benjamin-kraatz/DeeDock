import AppKit
import SwiftUI

/// A tab whose bottom corners flare outward (concave) so it reads as growing out of the window edge.
struct TabShape: Shape {
    var flare: CGFloat = Layout.flare
    var corner: CGFloat = 15
    var inverted = false
    var closed = true

    func path(in rect: CGRect) -> Path {
        let w = rect.width, h = rect.height, r = flare
        let c = min(corner, (w - 2 * r) / 2, h - r)
        var p = Path()
        p.move(to: CGPoint(x: 0, y: h))
        p.addQuadCurve(to: CGPoint(x: r, y: h - r), control: CGPoint(x: r, y: h))
        p.addLine(to: CGPoint(x: r, y: c))
        p.addQuadCurve(to: CGPoint(x: r + c, y: 0), control: CGPoint(x: r, y: 0))
        p.addLine(to: CGPoint(x: w - r - c, y: 0))
        p.addQuadCurve(to: CGPoint(x: w - r, y: c), control: CGPoint(x: w - r, y: 0))
        p.addLine(to: CGPoint(x: w - r, y: h - r))
        p.addQuadCurve(to: CGPoint(x: w, y: h), control: CGPoint(x: w - r, y: h))
        if closed { p.closeSubpath() }
        guard inverted else { return p }
        return p.applying(CGAffineTransform(scaleX: 1, y: -1).translatedBy(x: 0, y: -h))
    }
}

struct FaceView: View {
    @ObservedObject var eyes: EyeModel
    let phase: CompanionModel.Phase
    let compact: Bool

    private var openness: CGFloat {
        if eyes.blink { return 0.12 }
        return phase == .idle ? 0.28 : 1
    }

    var body: some View {
        let size = compact ? CGSize(width: 40, height: 26) : CGSize(width: 56, height: 32)
        let eye = compact ? CGSize(width: 7.5, height: 10) : CGSize(width: 10, height: 13)
        ZStack {
            RoundedRectangle(cornerRadius: size.height * 0.38, style: .continuous)
                .fill(Color(red: 0.17, green: 0.15, blue: 0.24))
                .shadow(color: .black.opacity(0.28), radius: 1.5, y: 1)
            VStack(spacing: compact ? 1 : 2) {
                HStack(spacing: size.width * 0.2) {
                    EyeView(size: eye, pupil: eyes.pupil, openness: openness)
                    EyeView(size: eye, pupil: eyes.pupil, openness: openness)
                }
                SmileShape()
                    .stroke(.white.opacity(0.9), style: StrokeStyle(lineWidth: 1.4, lineCap: .round))
                    .frame(width: compact ? 5 : 6, height: 2.5)
                    .opacity(phase == .idle ? 0 : 1)
                    .scaleEffect(phase == .answered ? 1.4 : 1)
            }
            .offset(y: compact ? 1 : 2)
        }
        .frame(width: size.width, height: size.height)
        .scaleEffect(phase == .awake ? 1.06 : 1)
        .animation(.spring(response: 0.28, dampingFraction: 0.55), value: phase)
        .animation(.easeInOut(duration: 0.09), value: eyes.blink)
        .contentShape(Rectangle())
        .accessibilityLabel("Companion")
        .accessibilityAddTraits(.isButton)
    }
}

struct EyeView: View {
    let size: CGSize
    let pupil: CGSize
    let openness: CGFloat

    var body: some View {
        ZStack {
            Capsule().fill(Color(white: 0.98))
            Circle()
                .fill(Color(red: 0.12, green: 0.10, blue: 0.18))
                .frame(width: size.width * 0.58, height: size.width * 0.58)
                .offset(x: pupil.width * size.width / 10, y: pupil.height * size.width / 10)
        }
        .frame(width: size.width, height: size.height)
        .clipShape(Capsule())
        .scaleEffect(x: 1, y: openness, anchor: .center)
        .animation(.spring(response: 0.3, dampingFraction: 0.7), value: openness)
    }
}

struct SmileShape: Shape {
    func path(in rect: CGRect) -> Path {
        var p = Path()
        p.move(to: CGPoint(x: rect.minX, y: rect.minY))
        p.addQuadCurve(to: CGPoint(x: rect.maxX, y: rect.minY), control: CGPoint(x: rect.midX, y: rect.maxY * 1.6))
        return p
    }
}

struct CompanionRoot: View {
    @ObservedObject var model: CompanionModel
    let eyes: EyeModel
    let actions: CompanionActions

    var body: some View {
        VStack(spacing: 0) {
            if model.placement == .above { Color.clear.frame(height: Layout.shadowMargin) }
            tab
            if model.phase == .prompting {
                SuggestionRow(model: model, actions: actions)
                    .padding(.top, 8)
                    .transition(.move(edge: model.placement == .above ? .top : .bottom).combined(with: .opacity))
            }
            if model.showsCard {
                AnswerCard(model: model, actions: actions)
                    .padding(.top, 8)
                    .transition(.scale(scale: 0.92, anchor: .top).combined(with: .opacity))
            }
            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .animation(.spring(response: 0.42, dampingFraction: 0.8), value: model.phase)
        .animation(.easeInOut(duration: 0.35), value: model.tintIsDark)
    }

    private var tab: some View {
        let inverted = model.placement == .inside
        return ZStack {
            TabShape(inverted: inverted)
                .fill(model.tint)
                .shadow(color: .black.opacity(0.16), radius: 4, y: inverted ? 2 : -1)
            TabShape(inverted: inverted, closed: false)
                .stroke(model.rim, lineWidth: 1)
            HStack(spacing: 10) {
                FaceView(eyes: eyes, phase: model.phase, compact: model.isBar)
                    .onTapGesture { actions.tapFace() }
                if model.phase == .selecting {
                    Text("Drag a region · click for the whole window · esc")
                        .font(.system(size: 11.5, weight: .medium))
                        .foregroundStyle(model.ink.opacity(0.72))
                        .lineLimit(1)
                        .fixedSize()
                        .transition(.opacity)
                }
                if model.isBar { PromptBar(model: model, actions: actions).transition(.opacity) }
            }
            .padding(.horizontal, Layout.flare + 7)
            .offset(y: inverted ? -1 : 2)
        }
        .frame(width: model.tabWidth, height: Layout.tabHeight)
    }
}

struct PromptBar: View {
    @ObservedObject var model: CompanionModel
    let actions: CompanionActions
    @FocusState private var focused: Bool

    var body: some View {
        HStack(spacing: 8) {
            if let context = model.context {
                Label(context.label, systemImage: context.symbol)
                    .font(.system(size: 11, weight: .semibold))
                    .lineLimit(1)
                    .padding(.horizontal, 8).padding(.vertical, 4)
                    .background(Capsule().fill(model.ink.opacity(0.10)))
                    .foregroundStyle(model.ink.opacity(0.85))
                    .frame(maxWidth: 170, alignment: .leading)
                    .fixedSize(horizontal: true, vertical: false)
            }
            TextField("Ask about this…", text: $model.prompt)
                .textFieldStyle(.plain)
                .font(.system(size: 13))
                .foregroundStyle(model.ink)
                .focused($focused)
                .disabled(model.phase == .thinking)
                .onSubmit { actions.submit(model.prompt) }
            if model.phase == .thinking { ProgressView().controlSize(.small) }
        }
        .onAppear { DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) { focused = true } }
        .onKeyPress(.escape) { actions.dismiss(); return .handled }
    }
}

struct SuggestionRow: View {
    @ObservedObject var model: CompanionModel
    let actions: CompanionActions
    private let suggestions: [(String, String, String)] = [
        ("Explain", "questionmark.bubble", "Explain this simply."),
        ("Translate", "character.bubble", "Translate this. If it is German, translate to English; otherwise translate to German."),
        ("Summarize", "text.alignleft", "Summarize this in three bullet points."),
        ("Do it", "wand.and.stars", "What should I do next here? If one menu command does it, propose it."),
    ]

    var body: some View {
        HStack(spacing: 6) {
            ForEach(suggestions, id: \.0) { item in
                Button { actions.submit(item.2) } label: {
                    Label(item.0, systemImage: item.1)
                        .font(.system(size: 11.5, weight: .medium))
                        .padding(.horizontal, 10).padding(.vertical, 6)
                        .background(Capsule().fill(.thinMaterial))
                        .overlay(Capsule().strokeBorder(.white.opacity(0.12)))
                }
                .buttonStyle(.plain)
            }
        }
    }
}

struct AnswerCard: View {
    @ObservedObject var model: CompanionModel
    let actions: CompanionActions

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            if model.answer.isEmpty {
                HStack(spacing: 8) {
                    ProgressView().controlSize(.small)
                    Text(model.busyLabel ?? "Thinking on-device…").font(.system(size: 12)).foregroundStyle(.secondary)
                }
            } else {
                ScrollView {
                    Text(model.answer)
                        .font(.system(size: 13))
                        .textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                .frame(maxHeight: 180)
            }
            if let action = model.proposedAction {
                Button { actions.runProposed() } label: {
                    Label("Run \(action)", systemImage: "play.fill").font(.system(size: 12, weight: .semibold))
                }
                .buttonStyle(.borderedProminent)
            }
            HStack(spacing: 8) {
                Button("Copy", action: actions.copy)
                if model.canReplace { Button("Replace selection", action: actions.replace) }
                Button("Paste into \(model.appName)", action: actions.paste)
                Spacer()
                if let toast = model.toast { Text(toast).font(.system(size: 11)).foregroundStyle(.secondary) }
                Button("Done", action: actions.dismiss).keyboardShortcut(.cancelAction)
            }
            .controlSize(.small)
            .disabled(model.phase != .answered)
        }
        .padding(14)
        .frame(width: Layout.cardWidth)
        .background(VisualEffect().clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous)))
        .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).strokeBorder(.white.opacity(0.10)))
        .shadow(color: .black.opacity(0.28), radius: 16, y: 8)
    }
}

/// Materials in a panel of an inactive app render in their inactive state unless forced active.
struct VisualEffect: NSViewRepresentable {
    func makeNSView(context: Context) -> NSVisualEffectView {
        let view = NSVisualEffectView()
        view.material = .popover
        view.blendingMode = .behindWindow
        view.state = .active
        return view
    }
    func updateNSView(_ nsView: NSVisualEffectView, context: Context) {}
}
