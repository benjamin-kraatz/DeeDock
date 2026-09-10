import SwiftUI

/// One pinned shortcut drawn as a plant, with watering as its primary action.
///
/// Watering does not introduce a second runner: the `water` closure is expected to call
/// ``ActionTilesController/water(_:)``, which is an alias of the existing Action Tiles `run`.
/// The button stays enabled for a wilted plant because only Shortcuts can decide whether a
/// missing identifier can still be run; it is disabled only while a run is in flight.
struct ShortcutGreenhousePlantView: View {
    let plant: ShortcutGreenhousePlant
    /// Runs the pinned shortcut behind this plant.
    let water: () -> Void
    /// Edge length of the plant artwork; the caption sizes itself.
    var size: CGFloat = 64

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var wilted: Bool { plant.health == .wilted }

    var body: some View {
        VStack(spacing: 4) {
            Button(action: water) {
                VStack(spacing: 6) {
                    ShortcutGreenhouseArtwork(health: plant.health, status: plant.status,
                                              size: size, reduceMotion: reduceMotion)
                        .modifier(ShortcutGreenhouseSway(active: swaying))
                    Text(verbatim: plant.tile.name)
                        .font(.caption)
                        .lineLimit(2)
                        .multilineTextAlignment(.center)
                    healthCaption
                }
                .frame(width: size * 1.6)
                .contentShape(.rect)
            }
            .buttonStyle(.plain)
            .disabled(!plant.canWater)
            .help(Text(helpText))
            .accessibilityLabel(Text(verbatim: plant.tile.name))
            .accessibilityValue(Text(accessibilityValue))
            .accessibilityHint(Text(.greenhouseWaterHint))
            if wilted {
                Text(.greenhouseWiltedHelp)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(width: size * 1.6)
                    .accessibilityHidden(true)
            }
        }
        .animation(reduceMotion ? nil : .easeInOut(duration: 0.25), value: plant.health)
    }

    /// Ambient sway is a decorative loop, so it stops for Reduce Motion and for a wilted plant.
    private var swaying: Bool { !reduceMotion && !wilted && !plant.status.busy }

    @ViewBuilder private var healthCaption: some View {
        if plant.status.busy && reduceMotion {
            ProgressView().controlSize(.mini)
        } else {
            Label {
                Text(plant.health.title)
            } icon: {
                Image(systemName: wilted ? "exclamationmark.triangle.fill" : "checkmark.seal.fill")
            }
            .font(.caption2)
            .foregroundStyle(wilted ? AnyShapeStyle(Color.orange)
                                    : AnyShapeStyle(HierarchicalShapeStyle.secondary))
        }
    }

    private var helpText: LocalizedStringResource {
        wilted ? .greenhouseWiltedHelp : .greenhouseWater
    }

    private var accessibilityValue: LocalizedStringResource {
        wilted ? .greenhouseWiltedValue(plant.status.title) : .greenhouseHealthyValue(plant.status.title)
    }
}

/// A slow decorative lean, used only where a continuous loop is acceptable.
///
/// The rotation anchors at the base so the pot stays still while the foliage moves, and the
/// modifier collapses to plain content when inactive so no animator is created at all.
private struct ShortcutGreenhouseSway: ViewModifier {
    let active: Bool

    func body(content: Content) -> some View {
        if active {
            content.phaseAnimator([-1.0, 1.0]) { view, phase in
                view.rotationEffect(.degrees(1.8 * phase), anchor: .bottom)
            } animation: { _ in
                .easeInOut(duration: 2.6)
            }
        } else {
            content
        }
    }
}

#if DEBUG
extension ShortcutGreenhousePlant {
    /// Deterministic sample plants for previews. No Shortcuts discovery is involved.
    static let previewHealthy = ShortcutGreenhousePlant(
        tile: ActionTile(id: UUID(uuidString: "00000000-0000-0000-0000-0000000000A1")!,
                         name: "Start Focus Session"),
        status: .idle,
        health: .healthy
    )
    static let previewWilted = ShortcutGreenhousePlant(
        tile: ActionTile(id: UUID(uuidString: "00000000-0000-0000-0000-0000000000A2")!,
                         name: "Archive Yesterday's Screenshots"),
        status: .failed("The shortcut could not be found."),
        health: .wilted
    )
    static let previewRunning = ShortcutGreenhousePlant(
        tile: ActionTile(id: UUID(uuidString: "00000000-0000-0000-0000-0000000000A3")!,
                         name: "Backup Notes"),
        status: .running,
        health: .healthy
    )
    static let previewSucceeded = ShortcutGreenhousePlant(
        tile: ActionTile(id: UUID(uuidString: "00000000-0000-0000-0000-0000000000A4")!,
                         name: "Toggle Dark Mode"),
        status: .succeeded,
        health: .healthy
    )

    static let previewBed: [ShortcutGreenhousePlant] = [
        .previewHealthy, .previewWilted, .previewRunning, .previewSucceeded,
    ]
}

#Preview("Healthy, idle") {
    ShortcutGreenhousePlantView(plant: .previewHealthy, water: {})
        .padding(24)
}

#Preview("Wilted") {
    ShortcutGreenhousePlantView(plant: .previewWilted, water: {})
        .padding(24)
}

#Preview("Running") {
    ShortcutGreenhousePlantView(plant: .previewRunning, water: {})
        .padding(24)
}

#Preview("Running, Reduce Motion") {
    ShortcutGreenhousePlantView(plant: .previewRunning, water: {})
        .padding(24)
}
#endif
