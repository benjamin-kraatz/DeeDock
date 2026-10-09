import SwiftUI

/// The DOKK tile: opens the DOKK Hub. A permanent utility tile that participates in the dock's
/// shared geometry and keyboard navigation.
///
/// Its position comes from ``LauncherDockPosition``. Dragging it, or the VoiceOver move actions
/// added by ``DockUtilityMoveModifier``, change that position.
///
/// Native docks draw the Glow tile: ``LauncherTileArtwork`` over a rainbow halo that brightens and
/// grows while the Hub is open and turns while the Hub is open or the pointer rests on the tile. A
/// progress ring circles the tile while the Hub's Files tab copies or moves in the background with
/// the Hub closed. Line docks draw the catalog's DOKK mark, lit while the Hub is open, like every
/// other line tile.
struct DockLauncherButton: View {
    let size: CGFloat
    let selected: Bool
    let interaction: DockInteraction
    let accessibilityFocus: (Bool) -> Void
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.dockTileHovered) private var tileHovered
    @AccessibilityFocusState private var focused: Bool

    private var hubOpen: Bool { interaction.hubTile?.isOpen == true }
    /// Transfer progress while the Hub is closed. An open Hub shows its own progress.
    private var ringProgress: Double? {
        guard let tile = interaction.hubTile, !tile.isOpen else { return nil }
        return tile.transferProgress()
    }

    var body: some View {
        let lineIcon = interaction.lineIcon(for: .launcher)
        let progress = ringProgress
        Button {
            interaction.openLauncher?()
        } label: {
            DockIconPresentation(
                size: size,
                edge: interaction.layout.edge,
                available: true,
                running: hubOpen,
                launching: false,
                keyboardSelected: selected,
                artworkOpacity: DockAppearanceOpacity(
                    settings: interaction.idleFade.settings,
                    idleFraction: interaction.idleFade.fraction,
                    reduceTransparency: reduceTransparency
                ).icons,
                artworkAnimation: interaction.idleFade.animation,
                lineIcon: lineIcon
            ) {
                ZStack {
                    // A resting dock pays nothing per frame: the halo only turns while it has a
                    // reason to (the Hub is open, or the pointer is on the tile) and the dock is shown.
                    DockHubTileHalo(size: size, open: hubOpen,
                                    turning: !reduceMotion && interaction.exposesContent && (hubOpen || tileHovered))
                    LauncherTileArtwork(size: size)
                        .phaseAnimator([1.0, 0.88, 1.0], trigger: interaction.hubTile?.pulse ?? 0) { view, scale in
                            view.scaleEffect(reduceMotion ? 1 : scale)
                        } animation: { _ in .spring(response: 0.22, dampingFraction: 0.55) }
                }
            }
            .overlay {
                if let progress {
                    DockHubTransferRing(progress: progress, diameter: size * 0.85 + 10)
                        .transition(.opacity)
                }
            }
            .animation(.easeOut(duration: 0.25), value: progress == nil)
            // The Hub points at this tile, so a line glyph keeps glowing while it is open.
            .transformEnvironment(\.dockTileHovered) { $0 = $0 || hubOpen }
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(Text(.hubTitle))
        .accessibilityHint(Text(.hubTileHint))
        .accessibilityValue(progress.map { Text(.hubTransferProgressLabel(Int(($0 * 100).rounded()))) } ?? Text(verbatim: ""))
        .accessibilityFocused($focused)
        .onChange(of: focused) { _, value in accessibilityFocus(value) }
        .onDisappear { accessibilityFocus(false) }
    }
}

/// The blurred conic rainbow behind the tile face (#ff4d6d #ff9f43 #ffd166 #4cc9f0 #4361ee
/// #b5179e), turning once every 9 seconds like the mockup's `spin` keyframes.
///
/// The gradient turns inside a fixed rounded mask, so the halo's outline stays put while its
/// colors travel. The angle comes from a `TimelineView` rather than a repeating animation: pausing
/// the timeline stops the turn on the same frame, and the angle it stopped at is kept so the next
/// start continues from there instead of snapping. Open, the halo springs from 55 % to full
/// opacity and from 7 to 10 points past the face. Reduce Motion (via `turning`) holds it still.
private struct DockHubTileHalo: View {
    let size: CGFloat
    let open: Bool
    /// Whether the gradient turns right now. The owner folds Reduce Motion and dock visibility in.
    let turning: Bool

    /// One full turn.
    private static let period: TimeInterval = 9

    /// The angle shown when the turn last stopped; the turn resumes from it.
    @State private var heldAngle: Double = 0
    /// When the current turn started.
    @State private var startedAt = Date()

    private static let colors: [Color] = [0xff4d6d, 0xff9f43, 0xffd166, 0x4cc9f0, 0x4361ee, 0xb5179e, 0xff4d6d]
        .map { Color(red: Double($0 >> 16 & 0xff) / 255, green: Double($0 >> 8 & 0xff) / 255, blue: Double($0 & 0xff) / 255) }

    var body: some View {
        TimelineView(.animation(minimumInterval: 1 / 30, paused: !turning)) { context in
            halo(angle: turning ? angle(at: context.date) : heldAngle)
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
        .onChange(of: turning) { _, turns in
            if turns {
                startedAt = .now
            } else {
                heldAngle = angle(at: .now)
            }
        }
    }

    private func angle(at date: Date) -> Double {
        let turns = date.timeIntervalSince(startedAt) / Self.period
        return (heldAngle + turns * 360).truncatingRemainder(dividingBy: 360)
    }

    private func halo(angle: Double) -> some View {
        let face = size * 0.85
        let reach: CGFloat = open ? 10 : 7
        let extent = face + reach * 2
        let shape = RoundedRectangle(cornerRadius: face * 0.26 + reach * 0.85, style: .continuous)
        return AngularGradient(colors: Self.colors, center: .center)
            .frame(width: extent * 1.5, height: extent * 1.5)
            .rotationEffect(.degrees(angle))
            .frame(width: extent, height: extent)
            .clipShape(shape)
            .blur(radius: face * 0.2)
            .opacity(open ? 1 : 0.55)
            .animation(HubStyle.motion, value: open)
    }
}

/// The accent progress ring around the tile while the Hub transfers files in the background.
private struct DockHubTransferRing: View {
    let progress: Double
    let diameter: CGFloat

    var body: some View {
        ZStack {
            Circle().stroke(Color(white: 0.5, opacity: 0.35), lineWidth: 3)
            Circle()
                .trim(from: 0, to: max(0.02, min(progress, 1)))
                .stroke(Color.accentColor, style: StrokeStyle(lineWidth: 3, lineCap: .round))
                .rotationEffect(.degrees(-90))
                .animation(.easeOut(duration: 0.2), value: progress)
        }
        .frame(width: diameter, height: diameter)
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}

#Preview("DOKK tile") {
    HStack(spacing: 28) {
        DockLauncherButton(size: 64, selected: false, interaction: DockInteraction(), accessibilityFocus: { _ in })
        DockLauncherButton(size: 48, selected: true, interaction: DockInteraction(), accessibilityFocus: { _ in })
    }
    .padding(40)
    .background(.black.opacity(0.6))
}

#Preview("Halo: resting, open, hovered") {
    @Previewable @State var open = false
    @Previewable @State var hovered = false
    VStack(spacing: 24) {
        HStack(spacing: 36) {
            ZStack {
                DockHubTileHalo(size: 64, open: false, turning: false)
                LauncherTileArtwork(size: 64)
            }
            ZStack {
                DockHubTileHalo(size: 64, open: open, turning: open || hovered)
                LauncherTileArtwork(size: 64)
            }
            ZStack {
                DockHubTileHalo(size: 64, open: true, turning: true)
                LauncherTileArtwork(size: 64)
            }
        }
        HStack {
            Toggle("Hub open", isOn: $open)
            Toggle("Hovered", isOn: $hovered)
        }
        .toggleStyle(.switch)
        .foregroundStyle(.white)
    }
    .padding(40)
    .background(.black.opacity(0.75))
}

#Preview("Transfer ring") {
    DockHubTransferRing(progress: 0.42, diameter: 64)
        .padding(30)
}
