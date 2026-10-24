import SwiftUI

/// The "Possibly related" fold (mockup `.sec.disc`). The chevron takes the rows' leading slot so the label
/// lines up with the other section headings, and the content isn't indented, so its checkboxes sit under
/// the data rows' checkboxes. The whole heading is the button.
///
/// The chevron turns on the Hub's spring; the sheet's height follows through ``HubUninstallSheet``. Under
/// Reduce Motion it snaps.
struct HubUninstallDisclosureStyle: DisclosureGroupStyle {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func makeBody(configuration: Configuration) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            Button {
                configuration.isExpanded.toggle()
            } label: {
                HStack(spacing: 9) {
                    Image(systemName: "chevron.right")
                        .font(.system(size: 9, weight: .bold))
                        .foregroundStyle(.tertiary)
                        .rotationEffect(.degrees(configuration.isExpanded ? 90 : 0))
                        .frame(width: 18)
                        .accessibilityHidden(true)
                    configuration.label
                }
                .hubUninstallSectionHeading()
                .contentShape(.rect)
            }
            .buttonStyle(.plain)
            // A plain button doesn't say whether it's open, as the native disclosure triangle does.
            .accessibilityValue(Text(configuration.isExpanded ? .sectionExpanded : .sectionCollapsed))
            .animation(reduceMotion ? nil : HubStyle.motion, value: configuration.isExpanded)
            if configuration.isExpanded {
                configuration.content
            }
        }
    }
}

extension DisclosureGroupStyle where Self == HubUninstallDisclosureStyle {
    /// ``HubUninstallDisclosureStyle``.
    static var hubUninstall: HubUninstallDisclosureStyle { HubUninstallDisclosureStyle() }
}
