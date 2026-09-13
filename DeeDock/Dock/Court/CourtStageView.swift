import SwiftUI
import AppKit

/// Transparent stage with bounded glass islands; no app-wide accessibility overrides.
struct CourtStageView: View {
    @Bindable var hearing: CourtHearing
    @State private var transcript = false
    @State private var lore = false
    @State private var accessibilityRevision = 0
    var previewReduceMotion: Bool? = nil
    var previewReduceTransparency: Bool? = nil
    var previewExpandedLore = false
    var regionsChanged: ([CGRect]) -> Void = { _ in }
    private var solid: Bool { previewReduceTransparency ?? NSWorkspace.shared.accessibilityDisplayShouldReduceTransparency }
    private var reducedMotion: Bool { previewReduceMotion ?? NSWorkspace.shared.accessibilityDisplayShouldReduceMotion }

    private var witnessVisible: Bool {
        hearing.witnessReady && (hearing.turns.contains { $0.role == .witness } || hearing.role == .witness)
    }
    private var speakerOffset: CGFloat {
        let roles: [CourtRole] = witnessVisible ? [.separation, .judge, .reconciliation, .witness] : [.separation, .judge, .reconciliation]
        return (CGFloat(roles.firstIndex(of: hearing.role) ?? 1) - CGFloat(roles.count - 1) / 2) * 152
    }

    var body: some View {
        VStack(spacing: 14) {
            HStack(alignment: .bottom, spacing: 24) {
                avatar(.separation)
                avatar(.judge)
                avatar(.reconciliation)
                if witnessVisible {
                    avatar(.witness)
                }
            }
            .frame(height: 112, alignment: .bottom)
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    CourtDragGrip(begin: { hearing.beginDrag?($0) })
                        .frame(width: 34, height: 24)
                        .accessibilityLabel(Text(.courtMove))
                    Text(.courtTitle).font(.headline)
                    Spacer()
                    if hearing.sample { Text(.courtSample).font(.caption).foregroundStyle(.secondary) }
                    Button(action: { hearing.close?() }) { Image(systemName: "xmark") }
                        .accessibilityLabel(Text(.courtClose))
                }
                Text(.courtAlreadyUnpinned).font(.caption).foregroundStyle(.secondary)
                HStack {
                    Text(hearing.status).font(.caption.weight(.semibold)).foregroundStyle(.tint)
                    Spacer()
                    if !hearing.finished && !hearing.failed && hearing.partial.isEmpty {
                        ProgressView().controlSize(.small).accessibilityLabel(Text(.courtWaiting))
                    }
                }
                VStack(alignment: .leading, spacing: 7) {
                    Label(hearing.speakerName, systemImage: hearing.role.symbol).font(.subheadline.bold())
                    Text(hearing.partial.isEmpty ? (hearing.generating ? String(localized: .courtWaiting) : (hearing.turns.last?.text ?? String(localized: .courtPreparingHelp))) : hearing.partial)
                        .font(.body).textSelection(.enabled)
                        .frame(maxWidth: .infinity, minHeight: 76, alignment: .topLeading)
                }
                .padding(12)
                .background(.primary.opacity(0.045), in: RoundedRectangle(cornerRadius: 14))
                .overlay(alignment: .top) {
                    CourtSpeechPointer().fill(.primary.opacity(0.045))
                        .frame(width: 18, height: 10).offset(x: speakerOffset, y: -10)
                        .accessibilityHidden(true)
                }
                .accessibilityElement(children: .combine)
                if hearing.failed {
                    HStack {
                        Text(.courtGenerationFailed).font(.caption)
                        Spacer()
                        Button(.courtRetry) { hearing.start() }
                    }
                }
                HStack(spacing: 10) {
                    Button(hearing.paused ? .courtResume : .courtPause) { hearing.togglePause() }
                        .disabled(hearing.finished || hearing.failed)
                    Button(.courtNext) { hearing.next() }.disabled(hearing.finished || hearing.failed)
                    Spacer()
                    Button(.courtLore) { lore.toggle(); transcript = false }
                    Button(.courtTranscript) { transcript.toggle(); lore = false }
                }
                if transcript || lore {
                    ScrollView {
                        VStack(alignment: .leading, spacing: 14) {
                            if transcript {
                                ForEach(hearing.turns) { turn in
                                    VStack(alignment: .leading, spacing: 4) {
                                        Text(turn.role.title).font(.caption.bold())
                                        Text(turn.text).textSelection(.enabled)
                                    }
                                }
                            } else {
                                Text(.courtFiction).font(.caption).foregroundStyle(.secondary)
                                ForEach(hearing.characters) { character in CourtBiographyView(character: character) }
                            }
                        }.frame(maxWidth: .infinity, alignment: .leading)
                    }.frame(height: 160)
                }
                Divider()
                HStack {
                    Button(.courtSkipForever) { hearing.skip?() }
                    Spacer()
                    Button(.courtPinAgain) { hearing.pinAgain() }.disabled(!hearing.canRestore)
                    Button(.courtClose) { hearing.close?() }
                }
                .font(.caption)
            }
            .padding(18)
            .background {
                if solid { RoundedRectangle(cornerRadius: 24).fill(Color(nsColor: .windowBackgroundColor)) }
                else { RoundedRectangle(cornerRadius: 24).fill(.clear).glassEffect(.regular, in: .rect(cornerRadius: 24)) }
            }
            .courtHitRegion()
        }
        .padding(16)
        .frame(width: 700)
        .coordinateSpace(name: "court")
        .onPreferenceChange(CourtHitRegions.self, perform: regionsChanged)
        .onAppear { lore = previewExpandedLore }
        .animation(reducedMotion ? nil : .easeInOut(duration: 0.2), value: hearing.role)
        .onReceive(NotificationCenter.default.publisher(for: NSWorkspace.accessibilityDisplayOptionsDidChangeNotification, object: nil)) { _ in accessibilityRevision += 1 }
        .id(accessibilityRevision)
        .accessibilityAction(named: Text(.courtMoveLeft)) { hearing.move?(-24, 0) }
        .accessibilityAction(named: Text(.courtMoveRight)) { hearing.move?(24, 0) }
        .accessibilityAction(named: Text(.courtMoveUp)) { hearing.move?(0, 24) }
        .accessibilityAction(named: Text(.courtMoveDown)) { hearing.move?(0, -24) }
    }

    private func avatar(_ role: CourtRole) -> some View {
        CourtAvatarView(role: role, app: role == .witness ? hearing.witnessApp : hearing.app,
                        active: hearing.role == role, reducedMotion: reducedMotion)
            .frame(width: 128)
            .courtHitRegion()
    }
}

private struct CourtSpeechPointer: Shape {
    func path(in rect: CGRect) -> Path {
        Path { path in
            path.move(to: CGPoint(x: rect.minX, y: rect.maxY))
            path.addLine(to: CGPoint(x: rect.midX, y: rect.minY))
            path.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY))
            path.closeSubpath()
        }
    }
}

private struct CourtAvatarView: View {
    let role: CourtRole
    let app: ApplicationReference?
    let active: Bool
    let reducedMotion: Bool
    var body: some View {
        VStack(spacing: 5) {
            ZStack(alignment: .bottomTrailing) {
                if role == .judge {
                    Image(systemName: "building.columns.circle.fill")
                        .resizable().symbolRenderingMode(.palette).foregroundStyle(.white, .indigo)
                        .frame(width: 58, height: 58)
                } else if let app {
                    Image(nsImage: NSWorkspace.shared.icon(forFile: app.url.path))
                        .resizable().frame(width: 58, height: 58)
                }
                Image(systemName: role.symbol)
                    .font(.system(size: 12, weight: .bold)).padding(6)
                    .background(.regularMaterial, in: Circle())
                    .offset(x: 7, y: 4)
            }
            .padding(7)
            .background(active ? Color.accentColor.opacity(0.22) : .clear, in: Circle())
            .scaleEffect(active && !reducedMotion ? 1.07 : 1)
            Text(role.title).font(.caption2.bold()).padding(.horizontal, 8).padding(.vertical, 4)
                .background(.regularMaterial, in: Capsule())
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text(role.title))
    }
}

struct CourtBiographyView: View {
    let character: CourtCharacter
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(character.appName).font(.headline)
            Text(character.biography)
            Text(character.counsel).font(.subheadline.bold())
            Text(character.counselBiography)
            Text(character.opposingCounsel).font(.subheadline.bold())
            Text(character.opposingBiography)
            Text(character.motive).italic()
            Text(character.incident)
            Text(character.relationship).foregroundStyle(.secondary)
        }.textSelection(.enabled)
    }
}

private struct CourtDragGrip: NSViewRepresentable {
    var begin: (NSEvent) -> Void
    final class Grip: NSView {
        var begin: ((NSEvent) -> Void)?
        override func mouseDown(with event: NSEvent) { begin?(event) }
        override func draw(_ dirtyRect: NSRect) {
            NSColor.secondaryLabelColor.setFill()
            for y in [8.0, 14.0] {
                for x in [10.0, 16.0, 22.0] { NSBezierPath(ovalIn: CGRect(x: x, y: y, width: 2, height: 2)).fill() }
            }
        }
    }
    func makeNSView(context: Context) -> Grip { let view = Grip(); view.begin = begin; return view }
    func updateNSView(_ nsView: Grip, context: Context) { nsView.begin = begin }
}

private struct CourtHitRegions: PreferenceKey {
    static var defaultValue: [CGRect] { [] }
    static func reduce(value: inout [CGRect], nextValue: () -> [CGRect]) { value += nextValue() }
}
private extension View {
    func courtHitRegion() -> some View {
        background(GeometryReader { proxy in
            Color.clear.preference(key: CourtHitRegions.self, value: [proxy.frame(in: .named("court"))])
        })
    }
}

#if DEBUG
#Preview("Court • ordinary") { CourtStageView(hearing: .preview()) }
#Preview("Court • witness streaming") { CourtStageView(hearing: .preview(witness: true, streaming: true)) }
#Preview("Court • preparation") { CourtStageView(hearing: .preview(loading: true)) }
#Preview("Court • accessible long lore") {
    CourtStageView(hearing: .preview(completed: true), previewReduceMotion: true,
                   previewReduceTransparency: true, previewExpandedLore: true)
        .preferredColorScheme(.light)
}
#Preview("Court • dark completed") {
    CourtStageView(hearing: .preview(completed: true)).preferredColorScheme(.dark)
}
#Preview("Court • failure") { CourtStageView(hearing: .preview(error: true)) }
#endif
