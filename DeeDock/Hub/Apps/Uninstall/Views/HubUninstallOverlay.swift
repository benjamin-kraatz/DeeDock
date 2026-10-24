import SwiftUI

/// The uninstall sheet over the Apps tab, as in `docs/mockups/hub-uninstall.html`: a veil dims the tab and
/// the sheet slides down from under the Hub's header on the Hub's spring (0.37, 0.89). It leaves on a short
/// ease-in, like a native sheet folding away. Reduce Motion crossfades both ways.
///
/// It sits in ``HubAppsView`` so it belongs to the Apps tab: switching tabs hides it with the tab. A
/// click on the veil does nothing; the sheet closes with Cancel, Done, or Escape.
struct HubUninstallOverlay: View {
    let uninstaller: HubAppsUninstaller

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.colorScheme) private var colorScheme

    /// Dismissal (mockup `cubic-bezier(.4,0,1,1)`, 0.26 s): quick, so the tab is back before the user looks for it.
    static let dismiss = Animation.timingCurve(0.4, 0, 1, 1, duration: 0.26)
    /// The veil's fade, independent of the sheet's spring so it never overshoots.
    static let veilFade = Animation.easeOut(duration: 0.25)
    static let crossfade = Animation.easeOut(duration: 0.2)
    /// Room kept under the sheet so its bottom corners stay inside the tab.
    static let bottomInset: CGFloat = 20

    var body: some View {
        GeometryReader { proxy in
            ZStack(alignment: .top) {
                if let session = uninstaller.session {
                    veil
                        .transition(.opacity.animation(reduceMotion ? Self.crossfade : Self.veilFade))
                    // The transition is on the sheet, not the full-height container, so the slide covers the
                    // sheet's own height (mockup `translateY(-104%)`) and not the whole tab's.
                    HubUninstallSheet(session: session, uninstaller: uninstaller,
                                      maxHeight: proxy.size.height - Self.bottomInset)
                        .id(session.id)
                        .transition(sheetTransition)
                }
            }
            .frame(width: proxy.size.width, height: proxy.size.height, alignment: .top)
            // Clipping to the tab is what makes the sheet appear from under the header.
            .clipped()
        }
        .animation(reduceMotion ? Self.crossfade : HubStyle.motion, value: uninstaller.session?.id)
    }

    /// Dark veil over a dark Hub; a light one washes out a light Hub instead of greying it (mockup `.dim`).
    private var veil: some View {
        (colorScheme == .dark ? Color.black.opacity(0.26) : Color.white.opacity(0.28))
            .contentShape(.rect)
            .onTapGesture {}
            .accessibilityHidden(true)
    }

    private var sheetTransition: AnyTransition {
        if reduceMotion { return .opacity.animation(Self.crossfade) }
        return .asymmetric(insertion: .move(edge: .top).animation(HubStyle.motion),
                           removal: .move(edge: .top).combined(with: .opacity).animation(Self.dismiss))
    }
}
