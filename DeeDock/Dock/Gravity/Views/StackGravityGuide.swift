import AppKit
import SwiftUI
import UniformTypeIdentifiers

/// An inert illustration of a gravity well: sample icons around one folder stack, drawn at their
/// pulled positions rather than at an even rest spacing.
///
/// Nothing here touches the live store, `UserDefaults`, or the user's applications: the artwork is
/// generic document-type iconography from `NSWorkspace`. Positions come from
/// ``StackGravityPhysics/pulledCenters(centers:wellIndices:configuration:)`` so the picture stays
/// honest when the physics constants change.
struct StackGravityGuide: View {
    /// Index of the folder stack inside ``samples``. The stack never moves; its neighbors do.
    private static let wellIndex = 2
    /// Icon edge in points. Large enough to read the folder glyph, small enough for a settings row.
    private static let iconSize: CGFloat = 34
    /// Gap between resting centers, before pull. Wide enough that the drift toward the stack reads.
    private static let restSpacing: CGFloat = 22

    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency

    /// OS-supplied artwork. Four generic bundles around a folder; never a user application.
    private static let samples: [UTType] = [
        .applicationBundle, .applicationBundle, .folder, .applicationBundle, .applicationBundle
    ]

    /// Resting centers on the along-axis, before gravity.
    private static let restingCenters: [CGFloat] = samples.indices.map {
        CGFloat($0) * (iconSize + restSpacing) + iconSize / 2
    }

    /// Centers after the demonstrative pull, computed once. The illustration is a fixed drawing,
    /// so full strength is used here regardless of the user's setting; the stack keeps its resting
    /// center by construction and only its neighbors move in.
    private static let pulledCenters = StackGravityPhysics.pulledCenters(
        centers: restingCenters,
        wellIndices: [wellIndex],
        configuration: StackGravityPhysics.Configuration(strength: 1, iconSize: iconSize, itemSpacing: restSpacing)
    )

    private var width: CGFloat {
        (Self.restingCenters.last ?? 0) + Self.iconSize / 2
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            surface
            Text(.stackGravityGuideHelp)
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        // One inert picture; VoiceOver reads the caption, not five decorative tiles.
        .accessibilityElement(children: .combine)
    }

    private var surface: some View {
        let centers = Self.pulledCenters
        return ZStack(alignment: .leading) {
            ForEach(Array(Self.samples.enumerated()), id: \.offset) { index, type in
                StackGravityGuideIcon(type: type, size: Self.iconSize, isWell: index == Self.wellIndex)
                    .offset(x: centers[index] - Self.iconSize / 2)
            }
        }
        .frame(width: width, height: Self.iconSize + 20, alignment: .leading)
        .padding(.horizontal, 12)
        .background(background)
        .accessibilityHidden(true)
    }

    @ViewBuilder private var background: some View {
        let shape = RoundedRectangle(cornerRadius: 12, style: .continuous)
        if reduceTransparency {
            shape.fill(.background.secondary)
        } else {
            shape.fill(.thinMaterial)
        }
    }
}

/// A single sample tile. The stack carries a faint ring so the attracting item stays identifiable
/// from a still picture; the guide never animates, so Reduce Motion needs no separate path.
private struct StackGravityGuideIcon: View {
    let type: UTType
    let size: CGFloat
    let isWell: Bool

    var body: some View {
        icon
            .frame(width: size, height: size)
            .overlay {
                if isWell {
                    RoundedRectangle(cornerRadius: size * 0.24, style: .continuous)
                        .strokeBorder(.tint.opacity(0.55), lineWidth: 2)
                        .padding(-3)
                }
            }
    }

    /// Generic type artwork from the OS, never a user application's icon.
    private var icon: some View {
        Image(nsImage: NSWorkspace.shared.icon(for: type))
            .resizable()
            .interpolation(.high)
            .aspectRatio(contentMode: .fit)
    }
}

#if DEBUG
#Preview("Gravity guide") {
    StackGravityGuide()
        .padding(24)
        .frame(width: SettingsMetrics.columnWidth)
}

#Preview("Gravity guide — Reduce Motion") {
    StackGravityGuide()
        .padding(24)
        .frame(width: SettingsMetrics.columnWidth)
}

#Preview("Gravity guide — dark, Reduce Transparency") {
    StackGravityGuide()
        .padding(24)
        .frame(width: SettingsMetrics.columnWidth)
        .preferredColorScheme(.dark)
}
#endif
