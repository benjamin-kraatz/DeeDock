import SwiftUI

/// The apps labelling never asks about, each with a button that asks about it again. A removed app slides out
/// toward the leading edge while the card closes up; Reduce Motion fades it.
struct AppHealthDontAskCard: View {
    /// Sorted by bundle identifier.
    let apps: [AppHealthAppDisplay]
    let allowAsking: (String) -> Void
    var reduceMotion = false

    private static let iconSize: CGFloat = 22
    private static let iconSpacing: CGFloat = 10
    /// Separators start at the name, past the icon, the way System Settings lists line up.
    static let dividerInset = SettingsMetrics.rowInset + iconSize + iconSpacing

    var body: some View {
        SettingsCard(title: .appHealthDontAskTitle, footnote: .appHealthDontAskHelp, dividerInset: Self.dividerInset) {
            ForEach(apps) { app in
                AppHealthDontAskRow(display: app, iconSize: Self.iconSize, iconSpacing: Self.iconSpacing) {
                    allowAsking(app.bundleID)
                }
                .transition(reduceMotion ? .opacity : .opacity.combined(with: .offset(x: -12)))
            }
        }
        .animation(reduceMotion ? .easeInOut(duration: 0.15) : .smooth(duration: 0.3), value: apps.map(\.id))
    }
}

/// One app on the "Don't ask" list: its icon and name from macOS, and a remove button that fills in on hover.
private struct AppHealthDontAskRow: View {
    let display: AppHealthAppDisplay
    let iconSize: CGFloat
    let iconSpacing: CGFloat
    let remove: () -> Void
    @State private var hovering = false

    var body: some View {
        HStack(spacing: iconSpacing) {
            Group {
                if let icon = display.icon {
                    Image(nsImage: icon).resizable().interpolation(.high)
                } else {
                    Image(systemName: "app.dashed").resizable().foregroundStyle(.secondary)
                }
            }
            .frame(width: iconSize, height: iconSize)
            .shadow(color: .black.opacity(0.15), radius: 1, y: 1)
            .accessibilityHidden(true)
            Text(verbatim: display.name)
                .lineLimit(1)
            Spacer(minLength: SettingsMetrics.controlSpacing)
            Button(action: remove) {
                Image(systemName: "minus.circle.fill")
                    .font(.body)
                    .foregroundStyle(hovering ? AnyShapeStyle(.primary) : AnyShapeStyle(.secondary))
                    .frame(width: 22, height: 22)
                    .contentShape(.circle)
            }
            .buttonStyle(.borderless)
            .onHover { hovering = $0 }
            .animation(.easeOut(duration: 0.12), value: hovering)
            .accessibilityLabel(Text(.appHealthDontAskRemove(app: display.name)))
            .help(Text(.appHealthDontAskRemove(app: display.name)))
        }
        .padding(.horizontal, SettingsMetrics.rowInset)
        .padding(.vertical, 8)
        .frame(maxWidth: .infinity, minHeight: SettingsMetrics.rowMinimumHeight, alignment: .leading)
        .accessibilityElement(children: .contain)
    }
}

#if DEBUG
#Preview("Not asked about") {
    let apps = [("com.example.Builder", "Builder", "hammer"), ("com.example.Mail", "Mail", "envelope"),
                ("com.example.Verwaltung", "Dokumentenverwaltung und Archivierungswerkzeug Professional", "archivebox")]
        .map { id, name, symbol in
            AppHealthAppDisplay(bundleID: id, name: name,
                                icon: NSImage(systemSymbolName: symbol, accessibilityDescription: nil))
        }
    AppHealthDontAskCard(apps: apps, allowAsking: { _ in })
        .tint(SettingsPage.appHealth.tint)
        .padding(24)
        .frame(width: SettingsMetrics.columnWidth)
}
#endif
