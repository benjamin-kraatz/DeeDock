import AppKit
import SwiftUI
import UniformTypeIdentifiers

/// One remembered drive in the Drives list: grip, icon, name and status, the show/hide eye, and
/// a menu for moving or forgetting it.
struct VolumeArrangementRow: View {
    let entry: VolumeArrangementEntry
    /// Finder's icon while the drive is mounted; nil while it is disconnected.
    let icon: NSImage?
    let canMoveUp: Bool
    let canMoveDown: Bool
    let setHidden: (Bool) -> Void
    /// Moves the drive by a number of rows.
    let move: (Int) -> Void
    let forget: () -> Void

    private var isConnected: Bool { icon != nil }

    var body: some View {
        HStack(spacing: 11) {
            Image(systemName: "line.3.horizontal")
                .font(.callout.weight(.medium))
                .foregroundStyle(.tertiary)
                .accessibilityHidden(true)
            VolumeArrangementIcon(icon: icon, kind: entry.kind)
                .opacity(entry.isHidden ? 0.4 : 1)
                .saturation(isConnected ? 1 : 0)
            VStack(alignment: .leading, spacing: 2) {
                Text(verbatim: entry.name)
                    .lineLimit(1)
                    .foregroundStyle(entry.isHidden ? .secondary : .primary)
                Text(subtitle)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            .layoutPriority(1)
            .accessibilityElement(children: .combine)
            Spacer(minLength: SettingsMetrics.controlSpacing)
            VolumeVisibilityButton(name: entry.name, isHidden: entry.isHidden, setHidden: setHidden)
            SettingsMoreMenu {
                Button(.dockModesMoveUp) { move(-1) }.disabled(!canMoveUp)
                Button(.dockModesMoveDown) { move(1) }.disabled(!canMoveDown)
                if !isConnected {
                    Divider()
                    Button(.settingsDriveForget, role: .destructive, action: forget)
                }
            }
        }
        .padding(.horizontal, SettingsMetrics.rowInset)
        .padding(.vertical, SettingsMetrics.rowVerticalInset)
        .frame(maxWidth: .infinity, minHeight: SettingsMetrics.rowMinimumHeight, alignment: .leading)
        .contentShape(.rect)
    }

    private var subtitle: LocalizedStringResource {
        let status = isConnected
            ? String(localized: .settingsDriveConnected)
            : String(localized: .settingsDriveLastConnected(when: entry.lastSeen.formatted(.relative(presentation: .named))))
        return .settingsDriveSubtitle(kind: String(localized: entry.kind.title), status: status)
    }
}

/// The eye that shows or hides a drive in the dock. The symbol swaps with a replace effect, so
/// the change reads as one control changing state.
private struct VolumeVisibilityButton: View {
    let name: String
    let isHidden: Bool
    let setHidden: (Bool) -> Void

    private var label: LocalizedStringResource {
        isHidden ? .settingsDriveShow(name: name) : .settingsDriveHide(name: name)
    }

    var body: some View {
        Button { setHidden(!isHidden) } label: {
            Image(systemName: isHidden ? "eye.slash" : "eye")
                .contentTransition(.symbolEffect(.replace))
                .foregroundStyle(isHidden ? AnyShapeStyle(.secondary) : AnyShapeStyle(.tint))
                .frame(width: 24, height: 22)
                .contentShape(.rect)
        }
        .buttonStyle(.borderless)
        .help(Text(label))
        .accessibilityLabel(Text(label))
    }
}

/// A drive's icon at list size with the same kind badge as its dock tile. Disconnected drives use
/// the generic volume icon, since their own icon can only be read while mounted.
struct VolumeArrangementIcon: View {
    let icon: NSImage?
    let kind: VolumeKind
    private static let size: CGFloat = 28

    var body: some View {
        Image(nsImage: icon ?? Self.placeholder)
            .resizable()
            .interpolation(.high)
            .frame(width: Self.size, height: Self.size)
            .overlay(alignment: .bottomTrailing) {
                DockVolumeBadge(kind: kind, ejecting: false, size: Self.size)
                    .scaleEffect(0.85)
                    .offset(x: 4, y: 3)
            }
            .accessibilityHidden(true)
    }

    private static let placeholder: NSImage = {
        let icon = NSWorkspace.shared.icon(for: .volume)
        icon.size = NSSize(width: 64, height: 64)
        return icon
    }()
}
