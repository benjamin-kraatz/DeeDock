import SwiftUI

/// A direct menu action. Opt-in, instructions, and saved marks belong in Settings.
struct QuarantineMenu: View {
    private let stamp = QuarantineStampController.shared
    var body: some View {
        if stamp.enabled {
            Button { stamp.toggle() } label: {
                Label {
                    Text(stamp.armed ? .quarantineDisarm : .quarantineArm)
                } icon: {
                    Image("QuarantineGlyph").resizable().scaledToFit().frame(width: 18, height: 18)
                }
            }
                .disabled(QuarantineStore.shared.unreadable)
        }
    }
}

/// Compact panel action, separate from folder presentation controls.
struct QuarantineToolbarButton: View {
    private let stamp = QuarantineStampController.shared
    var body: some View {
        if stamp.enabled {
            Button { stamp.toggle() } label: {
                Image("QuarantineGlyph").resizable().scaledToFit()
                    .frame(width: 20, height: 20)
                    .frame(width: 26, height: 22)
                    .padding(2)
                    .background(stamp.armed ? Color.accentColor.opacity(0.22) : .clear,
                                in: .rect(cornerRadius: 5))
            }
            .buttonStyle(.plain)
            .disabled(QuarantineStore.shared.unreadable)
            .accessibilityLabel(Text(stamp.armed ? .quarantineDisarm : .quarantineArm))
            .help(Text(stamp.armed ? .quarantineDisarm : .quarantineArm))
        }
    }
}
