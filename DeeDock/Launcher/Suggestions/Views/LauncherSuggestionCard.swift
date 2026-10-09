import SwiftUI

/// One suggested app as a card (mockup `.sc`): 44 pt icon, name, and a short reason.
///
/// Opening goes through ``LauncherState/openSuggested(_:)``, which rechecks that the app still
/// exists. Hover lifts the card 2 pt; Reduce Motion keeps it in place.
struct LauncherSuggestionCard: View {
    let application: LauncherApplication
    let state: LauncherState
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    @Environment(\.colorScheme) private var colorScheme
    @State private var icon: NSImage?
    @State private var hovered = false

    private var selected: Bool { state.selectedID == .suggested(application.id) }
    private var reason: LocalizedStringResource {
        LauncherSuggestionReason.text(for: application, history: state.history)
    }

    var body: some View {
        Button {
            state.openSuggested(application)
        } label: {
            HStack(spacing: 14) {
                artwork
                VStack(alignment: .leading, spacing: 2) {
                    Text(application.reference.name)
                        .font(.system(size: 14, weight: .semibold))
                        .lineLimit(1)
                    Text(reason)
                        .font(.system(size: 12))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
                Spacer(minLength: 0)
            }
            .padding(14)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(hovered ? HubAppsStyle.chip(colorScheme) : HubAppsStyle.card(colorScheme),
                        in: .rect(cornerRadius: HubStyle.cardRadius, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: HubStyle.cardRadius, style: .continuous)
                    .strokeBorder(selected ? Color.accentColor : HubAppsStyle.line(colorScheme),
                                  lineWidth: selected ? 2 : 0.5)
            }
            .contentShape(.rect(cornerRadius: HubStyle.cardRadius, style: .continuous))
        }
        .buttonStyle(.hubPress(scale: 0.98))
        .disabled(state.catalog.launching.contains(application.id))
        .offset(y: hovered && !reduceMotion ? -2 : 0)
        .onHover { hovered = $0 }
        .animation(reduceMotion ? nil : HubStyle.hover, value: hovered)
        .contextMenu {
            LauncherApplicationMenu(application: application, state: state, isSuggestion: true)
            Divider()
            LauncherSuggestionActions(application: application, state: state)
        }
        .task(id: application.reference.url) { icon = state.icon(for: application) }
        .accessibilityElement(children: .ignore)
        .accessibilityAddTraits(.isButton)
        .accessibilityLabel(Text(application.reference.name))
        .accessibilityValue(Text(reason))
        .accessibilityHint(Text(.hubAppsSuggestionHint))
        .accessibilityAddTraits(selected ? [.isSelected] : [])
        .accessibilityAction { state.openSuggested(application) }
        .accessibilityActions { LauncherSuggestionActions(application: application, state: state) }
        .help(Text(verbatim: application.reference.url.path))
    }

    @ViewBuilder private var artwork: some View {
        let size = HubAppsStyle.suggestionIconSize
        Group {
            if let lineIcon = state.lineIcon(for: application, artwork: icon) {
                DockLineIconArtwork(icon: lineIcon, size: size, hovered: hovered || selected,
                                    reduceMotion: reduceMotion, reduceTransparency: reduceTransparency,
                                    color: .primary)
            } else if let icon {
                Image(nsImage: icon).resizable().scaledToFit()
            } else {
                Image(systemName: "app.dashed").resizable().scaledToFit().foregroundStyle(.secondary)
            }
        }
        .frame(width: size, height: size)
        .accessibilityHidden(true)
    }
}

/// The second line on a suggestion card, built only from facts DOKK has: its own launch history.
///
/// The prediction model does not expose why it ranked an app, so the card never claims a cause
/// (such as "opened after Xcode"). Without DOKK history it says the suggestion comes from app use.
enum LauncherSuggestionReason {
    static func text(for application: LauncherApplication, history: LauncherHistory,
                     now: Date = Date(), calendar: Calendar = .current) -> LocalizedStringResource {
        guard let visit = history.visits[application.id], visit.lastOpened <= now else {
            return .hubAppsSuggestionReasonUsage
        }
        if calendar.isDate(visit.lastOpened, inSameDayAs: now) { return .hubAppsSuggestionReasonToday }
        let formatter = RelativeDateTimeFormatter()
        formatter.dateTimeStyle = .named
        formatter.unitsStyle = .full
        let relative = formatter.localizedString(for: visit.lastOpened, relativeTo: now)
        return .hubAppsSuggestionReasonLastOpened(relative)
    }
}
