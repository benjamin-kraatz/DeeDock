import SwiftUI

/// The action targets the exact frame that supplied this control.
struct WindowPreviewControl {
    let isRevealed: Bool
    let action: () -> Void
}

/// Places the privacy control over the artwork as a sibling of the window activation button.
struct WindowPreviewControls: View {
    let control: WindowPreviewControl

    var body: some View {
        if control.isRevealed {
            Button(action: control.action) {
                Image(systemName: "eye.slash")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(.white)
                    .frame(width: 27, height: 27)
                    .background(.black.opacity(0.75), in: .circle)
            }
            .buttonStyle(.plain)
            .accessibilityLabel(Text(.windowPreviewHide))
            .help(Text(.windowPreviewHideHelp))
            .padding(6)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomTrailing)
        } else {
            ViewThatFits {
                VStack(spacing: 8) {
                    Image(systemName: "eye.slash")
                        .font(.system(size: 20, weight: .medium))
                        .foregroundStyle(.secondary)
                        .accessibilityHidden(true)
                    showButton
                }
                .fixedSize()
                showButton.fixedSize()
                Button(action: control.action) {
                    Image(systemName: "eye")
                }
                .accessibilityLabel(Text(.windowPreviewReveal))
            }
            .buttonStyle(.bordered)
            .controlSize(.small)
            .help(Text(.windowPreviewRevealHelp))
            .padding(5)
        }
    }

    private var showButton: some View {
        Button(.windowPreviewReveal, action: control.action)
    }
}

/// Artwork for a covered, pending, or unavailable window preview.
struct WindowPreviewPlaceholder: View {
    let icon: NSImage?
    var covered = false
    var unavailable = false

    var body: some View {
        Rectangle().fill(.quaternary.opacity(0.55))
            .overlay {
                if !covered {
                    VStack(spacing: 6) {
                        if let icon {
                            Image(nsImage: icon)
                                .resizable()
                                .scaledToFit()
                                .frame(width: 28, height: 28)
                                .accessibilityHidden(true)
                        }
                        if unavailable {
                            Text(.windowPreviewUnavailable)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .multilineTextAlignment(.center)
                                .lineLimit(2)
                        }
                    }
                    .padding(5)
                }
            }
            .allowsHitTesting(false)
    }
}

enum WindowPreviewRevealShortcut {
    static func matches(_ event: NSEvent) -> Bool {
        event.keyCode == 15 &&
            event.modifierFlags.intersection([.command, .control, .option, .shift]) == .option
    }
}

#if DEBUG
#Preview("Window preview privacy") {
    HStack(spacing: 12) {
        WindowPreviewPlaceholder(icon: nil, covered: true)
            .overlay { WindowPreviewControls(control: .init(isRevealed: false, action: {})) }
        WindowPreviewPlaceholder(icon: NSImage(systemSymbolName: "app", accessibilityDescription: nil), unavailable: true)
        Rectangle().fill(.blue.gradient)
            .overlay { WindowPreviewControls(control: .init(isRevealed: true, action: {})) }
    }
    .clipShape(.rect(cornerRadius: 8))
    .frame(width: 520, height: 118)
    .padding()
}
#endif
