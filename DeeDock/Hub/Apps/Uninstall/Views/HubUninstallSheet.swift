import SwiftUI

/// The uninstall sheet: header, the scrolling notes and sections, and the footer; or the done view once
/// the app is in the Trash.
///
/// The body grows with its content up to `maxHeight` and scrolls beyond it. Height changes between
/// phases follow the Hub's spring, so the sheet folds into the done view instead of jumping.
struct HubUninstallSheet: View {
    let session: AppUninstallSession
    let uninstaller: HubAppsUninstaller
    /// The tallest the sheet may be inside the Apps tab.
    let maxHeight: CGFloat

    static let width: CGFloat = 600
    static let cornerRadius: CGFloat = 16
    /// Header and footer together, so the body knows what's left.
    private static let chromeHeight: CGFloat = 150

    /// Starts near a scanning sheet's height so the first frame doesn't jump; the spring takes it from there.
    @State private var contentHeight: CGFloat = 240
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency

    var body: some View {
        let shape = UnevenRoundedRectangle(bottomLeadingRadius: Self.cornerRadius,
                                           bottomTrailingRadius: Self.cornerRadius, style: .continuous)
        VStack(spacing: 0) {
            if case .done(let summary) = session.phase {
                HubUninstallDoneView(session: session, summary: summary, uninstaller: uninstaller)
                    .transition(.opacity)
            } else {
                HubUninstallHeader(session: session)
                ScrollView {
                    HubUninstallContent(session: session, uninstaller: uninstaller)
                        .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { contentHeight = $0 }
                }
                .scrollBounceBehavior(.basedOnSize)
                .frame(height: min(contentHeight, max(maxHeight - Self.chromeHeight, 120)))
                HubUninstallFooter(session: session, uninstaller: uninstaller)
            }
        }
        .frame(width: Self.width)
        .background { HubUninstallSheetBackground(shape: shape, opaque: reduceTransparency) }
        .clipShape(shape)
        .overlay { shape.strokeBorder(Color.primary.opacity(0.14), lineWidth: 0.5) }
        .shadow(color: .black.opacity(0.32), radius: 30, y: 18)
        .animation(reduceMotion ? nil : HubStyle.motion, value: contentHeight)
        .animation(reduceMotion ? .easeOut(duration: 0.2) : HubStyle.motion, value: session.phase)
        .accessibilityElement(children: .contain)
        .accessibilityAddTraits(.isModal)
        .accessibilityLabel(Text(.hubUninstallTitle(name: session.appName)))
    }
}

/// The notes and sections between the header and the footer.
private struct HubUninstallContent: View {
    let session: AppUninstallSession
    let uninstaller: HubAppsUninstaller

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HubUninstallNotices(session: session, uninstaller: uninstaller)
            HubUninstallAppSection(session: session)
            HubUninstallDataSection(session: session)
            if !session.relatedItems.isEmpty {
                HubUninstallRelatedSection(session: session)
            }
        }
        .padding(EdgeInsets(top: 0, leading: 22, bottom: 10, trailing: 22))
        .animation(reduceMotion ? nil : HubStyle.motion, value: session.itemProgress)
    }
}

/// Frosted material over the Hub's glass, or an opaque fill under Reduce Transparency (the mockup's
/// `--sheet`: `#23242b` dark, `#f7f7f9` light).
private struct HubUninstallSheetBackground: View {
    let shape: UnevenRoundedRectangle
    let opaque: Bool

    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        if opaque {
            shape.fill(colorScheme == .dark ? Color(red: 35 / 255, green: 36 / 255, blue: 43 / 255)
                : Color(red: 247 / 255, green: 247 / 255, blue: 249 / 255))
        } else {
            shape.fill(.regularMaterial)
        }
    }
}
