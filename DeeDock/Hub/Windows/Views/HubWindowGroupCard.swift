import SwiftUI

/// One app's windows: a rounded card with the app's icon, name, and window count above its
/// window cards. The cards wrap when an app has more windows than fit across.
struct HubWindowGroupCard: View {
    let group: HubWindowGroup
    let icon: NSImage?
    let thumbnails: [CGWindowID: CGImage]
    let selection: String?
    let reduceMotion: Bool
    let activate: (HubWindowItem) -> Void
    /// Receives each card's frame in ``HubWindowsView/gridSpace`` for arrow-key navigation.
    let reportFrame: (String, CGRect) -> Void
    @Environment(\.colorScheme) private var colorScheme

    private var shape: RoundedRectangle { RoundedRectangle(cornerRadius: 18, style: .continuous) }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            header
            HubWindowsWrapLayout(spacing: 12, lineSpacing: 14) {
                ForEach(group.windows) { item in
                    HubWindowCard(item: item, appName: group.name, icon: icon,
                                  thumbnail: item.window.captureID.flatMap { thumbnails[$0] },
                                  isSelected: selection == item.id, reduceMotion: reduceMotion) {
                        activate(item)
                    }
                    .id(item.id)
                    .onGeometryChange(for: CGRect.self) { $0.frame(in: .named(HubWindowsView.gridSpace)) } action: {
                        reportFrame(item.id, $0)
                    }
                }
            }
        }
        .padding(.top, 12)
        .padding(.horizontal, 14)
        .padding(.bottom, 14)
        .background(shape.fill(colorScheme == .dark ? Color.white.opacity(0.045) : Color.white.opacity(0.5)))
        .overlay(shape.strokeBorder(colorScheme == .dark ? Color.white.opacity(0.08) : Color.black.opacity(0.075),
                                    lineWidth: 0.5))
        .accessibilityElement(children: .contain)
        .accessibilityLabel(Text(verbatim: group.name))
    }

    private var header: some View {
        HStack(spacing: 9) {
            if let icon {
                Image(nsImage: icon)
                    .resizable()
                    .interpolation(.high)
                    .frame(width: 22, height: 22)
                    .accessibilityHidden(true)
            }
            Text(verbatim: group.name)
                .font(.system(size: 13.5, weight: .semibold))
                .lineLimit(1)
            Text(group.windows.count, format: .number)
                .font(.system(size: 13.5))
                .foregroundStyle(.tertiary)
                .accessibilityLabel(Text(.hubWindowsWindowCount(group.windows.count)))
        }
        .padding(.horizontal, 2)
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.isHeader)
    }
}
