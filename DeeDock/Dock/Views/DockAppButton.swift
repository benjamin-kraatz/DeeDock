import SwiftUI

/// An app icon with running, launch-progress, selection, and accessibility states.
///
/// `open` and `togglePin` express user intent; this component never invokes workspace APIs itself.
struct DockAppButton: View {
    let item: DockItem
    /// Current magnified icon dimension in logical points; indicator space is additional.
    let size: CGFloat
    let isLaunching: Bool
    let isSelected: Bool
    let open: () -> Void
    let togglePin: () -> Void

    var body: some View {
        Button(action: open) {
            VStack(spacing: 6) {
                Image(nsImage: item.icon).resizable().interpolation(.high)
                    .frame(width: size, height: size)
                    .opacity(item.isAvailable ? 1 : 0.4)
                    .overlay {
                        if isLaunching {
                            Circle().fill(.black.opacity(0.14))
                        }
                        if isSelected {
                            RoundedRectangle(cornerRadius: 12)
                                .strokeBorder(Color.accentColor, lineWidth: 2)
                        }
                    }
                    .overlay {
                        if isLaunching {
                            ProgressView().controlSize(.small)
                                .padding(8)
                                .glassEffect(.clear)
                        }
                    }
                if !isSelected {
                    Circle().fill(.primary.opacity(item.isRunning ? 0.8 : 0))
                        .frame(width: 4, height: 4)
                } else {
                    RoundedRectangle(cornerRadius: 2).fill(.primary)
                        .frame(width: 16, height: 4)
                }
            }
            .frame(width: size, height: size + 12)
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .disabled(isLaunching)
        .contextMenu {
            if item.isAvailable {
                Button(.actionOpen, systemImage: "arrow.up.forward.app", action: open)
            }
            Divider()
            Button(
                item.isFavorite ? .actionUnpin : .actionPin,
                systemImage: item.isFavorite ? "pin.slash" : "pin",
                action: togglePin
            )
        }
        .accessibilityLabel(Text(verbatim: item.reference.name))
        .accessibilityValue(Text(item.isAvailable ? (item.isRunning ? .appStatusRunning : .appStatusNotRunning) : .appStatusUnavailable))
        .accessibilityHint(Text(.appOpenHint))
        .accessibilityAction(named: Text(item.isFavorite ? .actionUnpin : .actionPin), togglePin)
    }
}

#if DEBUG
#Preview("Running, launching, unavailable") {
    HStack(spacing: 20) {
        DockAppButton(item: DockPreviewData.items[0], size: 48, isLaunching: false, isSelected: true,
                      open: {}, togglePin: {})
        DockAppButton(item: DockPreviewData.items[1], size: 48, isLaunching: true, isSelected: false,
                      open: {}, togglePin: {})
        DockAppButton(item: DockPreviewData.items[2], size: 48, isLaunching: false, isSelected: false,
                      open: {}, togglePin: {})
    }
    .padding(20)
}
#endif
