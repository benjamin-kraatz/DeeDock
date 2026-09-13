import SwiftUI

/// A notice inside a card: a status glyph, a short message, and the one or two actions that resolve it.
///
/// Used where a setting needs attention (a missing permission, an unreadable file) so the fix sits
/// on the same line as the problem instead of in a separate row of buttons.
struct SettingsStatusRow<Accessory: View>: View {
    let symbol: String
    let tint: Color
    let message: Text
    @ViewBuilder var accessory: Accessory

    var body: some View {
        HStack(alignment: .center, spacing: 10) {
            Image(systemName: symbol)
                .foregroundStyle(tint)
                .accessibilityHidden(true)
            message
                .font(.callout)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .leading)
            accessory
        }
        .padding(.horizontal, SettingsMetrics.rowInset)
        .padding(.vertical, 10)
        .frame(maxWidth: .infinity, minHeight: SettingsMetrics.rowMinimumHeight, alignment: .leading)
    }
}

extension SettingsStatusRow where Accessory == EmptyView {
    init(symbol: String, tint: Color, message: Text) {
        self.init(symbol: symbol, tint: tint, message: message) { EmptyView() }
    }
}

/// The ellipsis menu that holds a row's secondary actions, so a row shows at most one button.
struct SettingsMoreMenu<Content: View>: View {
    var label = Text(.settingsMoreActions)
    @ViewBuilder var content: Content

    var body: some View {
        Menu { content } label: {
            Image(systemName: "ellipsis.circle")
                .foregroundStyle(.secondary)
        }
        .menuStyle(.borderlessButton)
        .menuIndicator(.hidden)
        .fixedSize()
        .accessibilityLabel(label)
        .help(label)
    }
}

/// The bottom edge of a list card: borderless add and reload controls, leading-aligned the way
/// macOS places a list's + and − buttons.
struct SettingsListFooter<Content: View>: View {
    @ViewBuilder var content: Content

    var body: some View {
        HStack(spacing: 16) {
            content
            Spacer(minLength: 0)
        }
        .buttonStyle(.borderless)
        .padding(.horizontal, SettingsMetrics.rowInset)
        .padding(.vertical, 9)
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

/// A whole-row button that opens something else, such as a history window, drawn like a link row.
struct SettingsButtonRow: View {
    let title: LocalizedStringResource
    var systemImage = "arrow.up.forward.app"
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack {
                Text(title)
                Spacer(minLength: SettingsMetrics.controlSpacing)
                Image(systemName: systemImage)
                    .font(.callout)
                    .foregroundStyle(.tertiary)
                    .accessibilityHidden(true)
            }
            .padding(.horizontal, SettingsMetrics.rowInset)
            .padding(.vertical, SettingsMetrics.rowVerticalInset)
            .frame(maxWidth: .infinity, minHeight: SettingsMetrics.rowMinimumHeight, alignment: .leading)
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
    }
}

/// One macOS permission: what it is, whether DDock has it, and the single action that grants it.
/// Re-checking and opening System Settings live in the row's menu.
struct SettingsPermissionRow: View {
    enum State { case granted, missing, unavailable }

    let symbol: String
    let colors: [Color]
    let title: LocalizedStringResource
    let status: LocalizedStringResource
    let state: State
    let enableTitle: LocalizedStringResource
    let request: () -> Void
    let refresh: () -> Void
    let openSettings: () -> Void

    var body: some View {
        HStack(spacing: 11) {
            SettingsIconTile(glyph: .symbol(symbol), colors: colors, size: 28)
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                Text(status)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .layoutPriority(1)
            Spacer(minLength: SettingsMetrics.controlSpacing)
            switch state {
            case .granted:
                Label(.settingsPermissionGranted, systemImage: "checkmark.circle.fill")
                    .foregroundStyle(.green)
            case .missing:
                Button(enableTitle, action: request)
                    .buttonStyle(.borderedProminent)
            case .unavailable:
                EmptyView()
            }
            SettingsMoreMenu {
                Button(.windowAccessCheckAgain, action: refresh)
                Button(.windowAccessOpenSettings, action: openSettings)
            }
        }
        .padding(.horizontal, SettingsMetrics.rowInset)
        .padding(.vertical, 10)
        .frame(maxWidth: .infinity, minHeight: 52, alignment: .leading)
        .accessibilityElement(children: .contain)
    }
}

#if DEBUG
#Preview("List rows") {
    VStack(spacing: SettingsMetrics.cardSpacing) {
        SettingsCard {
            SettingsPermissionRow(symbol: "macwindow", colors: SettingsPage.windowPeek.tileColors,
                                  title: .windowAccessTitle, status: .windowAccessStatusEnabled, state: .granted,
                                  enableTitle: .windowAccessEnable, request: {}, refresh: {}, openSettings: {})
            SettingsPermissionRow(symbol: "rectangle.dashed.badge.record", colors: SettingsPage.badges.tileColors,
                                  title: .screenCaptureAccessTitle, status: .screenCaptureAccessStatusNotEnabled,
                                  state: .missing, enableTitle: .screenCaptureAccessEnable,
                                  request: {}, refresh: {}, openSettings: {})
            SettingsStatusRow(symbol: "exclamationmark.triangle.fill", tint: .orange,
                              message: Text(.appBadgesPermission)) {
                Button(.windowAccessEnable) {}
            }
            SettingsButtonRow(title: .badgeMemoryReview) {}
            SettingsListFooter {
                Button(.dockModesNew, systemImage: "plus") {}
            }
        }
    }
    .padding(24)
    .frame(width: 640)
}
#endif
