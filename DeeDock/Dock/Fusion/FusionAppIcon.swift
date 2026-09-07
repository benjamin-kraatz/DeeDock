import SwiftUI

/// The real application icon for a source window, so a card is recognisable at a glance.
///
/// Icons are resolved through the shared per-bundle cache: the tray is opened repeatedly and each
/// step redraws the same two icons, so re-reading the bundles on every appearance is wasted work.
struct FusionAppIcon: View {
    let bundleIdentifier: String?
    var size: CGFloat = 32

    var body: some View {
        Group {
            if let image = SessionCapsuleApplicationIcons.icon(for: bundleIdentifier) {
                Image(nsImage: image).resizable().interpolation(.high)
            } else {
                Image(systemName: "macwindow").resizable().scaledToFit()
                    .foregroundStyle(.secondary).padding(size * 0.1)
            }
        }
        .scaledToFit()
        .frame(width: size, height: size)
        .accessibilityHidden(true)
    }
}
