import SwiftUI

/// The uninstall sheet over the Apps tab, as in `docs/mockups/hub-uninstall.html`: a veil dims the tab and
/// the sheet slides down from under the Hub's header on the Hub's spring (0.37, 0.89). Reduce Motion
/// crossfades instead.
///
/// It sits in ``HubAppsView`` so it belongs to the Apps tab: switching tabs hides it with the tab. A
/// click on the veil does nothing; the sheet closes with Cancel, Done, or Escape.
struct HubUninstallOverlay: View {
    let uninstaller: HubAppsUninstaller

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        ZStack(alignment: .top) {
            if let session = uninstaller.session {
                Color.black.opacity(colorScheme == .dark ? 0.26 : 0.14)
                    .contentShape(.rect)
                    .onTapGesture {}
                    .accessibilityHidden(true)
                    .transition(.opacity)
                GeometryReader { proxy in
                    HubUninstallSheet(session: session, uninstaller: uninstaller, maxHeight: proxy.size.height - 20)
                        .frame(maxWidth: .infinity, alignment: .top)
                }
                .id(session.id)
                .transition(reduceMotion ? .opacity : .move(edge: .top))
            }
        }
        .animation(reduceMotion ? .easeOut(duration: 0.2) : HubStyle.motion, value: uninstaller.session?.id)
        .clipped()
    }
}
