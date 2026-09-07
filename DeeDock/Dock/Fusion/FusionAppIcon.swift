import SwiftUI

struct FusionAppIcon: View {
    let bundleIdentifier: String?
    var body: some View {
        Group {
            if let bundleIdentifier, let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleIdentifier) {
                Image(nsImage: NSWorkspace.shared.icon(forFile: url.path)).resizable()
            } else { Image(systemName: "macwindow").resizable() }
        }.scaledToFit().frame(width: 32, height: 32).accessibilityHidden(true)
    }
}
