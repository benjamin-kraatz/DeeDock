import SwiftUI

/// Quarantine stamp settings bound to the shared stamp controller and flag store.
struct QuarantineSettingsCard: View {
    @Bindable private var stamp = QuarantineStampController.shared
    private let store = QuarantineStore.shared

    var body: some View {
        QuarantineSettingsContent(
            enabled: stamp.enabled,
            armed: stamp.armed,
            unreadable: store.unreadable,
            error: store.error,
            records: store.records,
            armSound: $stamp.armSound,
            stampSound: $stamp.stampSound,
            releaseSound: $stamp.releaseSound,
            setEnabled: { stamp.enabled = $0 },
            toggleArmed: { stamp.toggle() },
            release: { stamp.release($0) },
            previewSound: { stamp.preview($0) })
    }
}

/// The settings rendering, driven by plain values so each state is previewable.
///
/// Only the hero card is visible while the feature is off. Everything that configures or uses
/// the stamp collapses with it, because none of it has an effect until the switch is on.
struct QuarantineSettingsContent: View {
    let enabled: Bool
    let armed: Bool
    /// True when saved flags could not be decoded; the store fails closed and the switch locks.
    let unreadable: Bool
    let error: String?
    let records: [QuarantineStore.Record]
    @Binding var armSound: Bool
    @Binding var stampSound: Bool
    @Binding var releaseSound: Bool
    let setEnabled: (Bool) -> Void
    let toggleArmed: () -> Void
    let release: (QuarantineStore.Record) -> Void
    let previewSound: (String) -> Void

    /// The switch animates the transaction itself, so cards below this one on the page slide
    /// along with the collapse instead of jumping.
    private var enabledBinding: Binding<Bool> {
        Binding(get: { enabled }, set: { value in
            withAnimation(.smooth(duration: 0.35)) { setEnabled(value) }
        })
    }

    var body: some View {
        VStack(alignment: .leading, spacing: SettingsMetrics.cardSpacing) {
            SettingsCard(title: .quarantineTitle, footnote: .quarantineSettingsHelp) {
                QuarantineHeroRow(enabled: enabledBinding, locked: unreadable)
                if let error {
                    QuarantineSettingsNotice(symbol: "exclamationmark.triangle.fill", tint: .orange,
                                             message: Text(verbatim: error))
                }
                if !enabled && !records.isEmpty && !unreadable {
                    QuarantineSettingsNotice(symbol: "seal.fill", tint: .quarantineStamp,
                                             message: Text(.quarantineDisabledPending))
                }
            }
            if enabled {
                VStack(alignment: .leading, spacing: SettingsMetrics.cardSpacing) {
                    SettingsCard(title: .quarantineHowTitle) {
                        SettingsStackedRow { QuarantineStepsView() }
                        QuarantineArmRow(armed: armed, disabled: unreadable, toggle: toggleArmed)
                    }
                    SettingsCard(title: .quarantineItemsTitle) {
                        if records.isEmpty {
                            QuarantineEmptyRow()
                        } else {
                            if !armed {
                                QuarantineSettingsNotice(symbol: "info.circle", tint: .secondary,
                                                         message: Text(.quarantineItemsArmHint))
                            }
                            ForEach(records) { record in
                                QuarantineRecordRow(record: record, armed: armed) { release(record) }
                            }
                        }
                    }
                    SettingsCard(title: .quarantineSoundsTitle) {
                        QuarantineSoundRow(title: .quarantineSoundArm, isOn: $armSound) { previewSound("arm") }
                        QuarantineSoundRow(title: .quarantineSoundStamp, isOn: $stampSound) { previewSound("stamp") }
                        QuarantineSoundRow(title: .quarantineSoundRelease, isOn: $releaseSound) { previewSound("undo") }
                    }
                }
                .transition(.asymmetric(insertion: .opacity.combined(with: .offset(y: -8)),
                                        removal: .opacity))
            }
        }
    }
}

/// Illustration, name, one-line promise, and the feature switch, on a surface warmed by the
/// stamp's ink while it is on.
private struct QuarantineHeroRow: View {
    @Binding var enabled: Bool
    let locked: Bool

    var body: some View {
        HStack(spacing: 14) {
            QuarantineStampHero(active: enabled)
            VStack(alignment: .leading, spacing: 3) {
                Text(.quarantineEnable)
                    .font(.headline)
                Text(.quarantineTagline)
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .layoutPriority(1)
            Spacer(minLength: SettingsMetrics.controlSpacing)
            Toggle(isOn: $enabled) { Text(.quarantineEnable) }
                .labelsHidden()
                .toggleStyle(.switch)
                .disabled(locked)
        }
        .padding(.leading, 8)
        .padding(.trailing, SettingsMetrics.rowInset)
        .padding(.vertical, 10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background {
            RadialGradient(colors: [Color.quarantineStamp.opacity(0.2), .clear],
                           center: .leading, startRadius: 0, endRadius: 260)
                .opacity(enabled ? 1 : 0)
        }
    }
}

/// The arm button with what to expect next: how to leave the mode, or that it is live.
private struct QuarantineArmRow: View {
    let armed: Bool
    let disabled: Bool
    let toggle: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            Group {
                if armed {
                    Label {
                        Text(.quarantineArmed)
                    } icon: {
                        Circle()
                            .fill(Color.quarantineStamp)
                            .frame(width: 7, height: 7)
                            .phaseAnimator([1.0, 0.35]) { dot, phase in dot.opacity(phase) }
                    }
                    .foregroundStyle(Color.quarantineStamp)
                } else {
                    Text(.quarantinePutAwayHint)
                        .foregroundStyle(.secondary)
                }
            }
            .font(.caption)
            .fixedSize(horizontal: false, vertical: true)
            .layoutPriority(1)
            Spacer(minLength: SettingsMetrics.controlSpacing)
            Button(action: toggle) {
                Label {
                    Text(armed ? .quarantineDisarm : .quarantineArm)
                } icon: {
                    Image("QuarantineGlyph").resizable().scaledToFit().frame(width: 16, height: 16)
                }
            }
            .buttonStyle(.borderedProminent)
            .tint(armed ? .gray : .quarantineStamp)
            .disabled(disabled)
        }
        .padding(.horizontal, SettingsMetrics.rowInset)
        .padding(.vertical, 10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .animation(.smooth(duration: 0.2), value: armed)
    }
}

private struct QuarantineEmptyRow: View {
    var body: some View {
        HStack(spacing: 10) {
            Image("QuarantineInk")
                .resizable()
                .frame(width: 22, height: 22)
                .saturation(0)
                .opacity(0.35)
                .accessibilityHidden(true)
            Text(.quarantineItemsEmpty)
                .foregroundStyle(.secondary)
        }
        .padding(.horizontal, SettingsMetrics.rowInset)
        .frame(maxWidth: .infinity, minHeight: SettingsMetrics.rowMinimumHeight, alignment: .leading)
    }
}

#if DEBUG
private let previewRecords: [QuarantineStore.Record] = [
    .init(id: "com.apple.TextEdit", url: URL(filePath: "/System/Applications/TextEdit.app"),
          name: "TextEdit", stampedAt: .now.addingTimeInterval(-3_600)),
    .init(id: "shelf.report", url: URL(filePath: "/Users/Shared/Quarterly Report Final v3.pdf"),
          name: "Quarterly Report Final v3.pdf", stampedAt: .now.addingTimeInterval(-86_400 * 2)),
]

private struct QuarantineSettingsPreview: View {
    @State var enabled: Bool
    @State var armed = false
    var records: [QuarantineStore.Record] = previewRecords
    var error: String?
    @State private var sounds = [true, true, false]

    var body: some View {
        ScrollView {
            QuarantineSettingsContent(
                enabled: enabled, armed: armed, unreadable: error != nil, error: error, records: records,
                armSound: $sounds[0], stampSound: $sounds[1], releaseSound: $sounds[2],
                setEnabled: { enabled = $0 }, toggleArmed: { armed.toggle() },
                release: { _ in }, previewSound: { _ in })
            .padding(24)
        }
        .frame(width: SettingsMetrics.columnWidth, height: 760)
    }
}

#Preview("Off, items pending") { QuarantineSettingsPreview(enabled: false) }
#Preview("On, dark") { QuarantineSettingsPreview(enabled: true).preferredColorScheme(.dark) }
#Preview("On, armed") { QuarantineSettingsPreview(enabled: true, armed: true) }
#Preview("On, empty") { QuarantineSettingsPreview(enabled: true, records: []) }
#Preview("Unreadable") {
    QuarantineSettingsPreview(enabled: false, records: [],
                              error: "DDock could not read or save quarantine flags. Existing data has been preserved.")
}
#Preview("German") {
    QuarantineSettingsPreview(enabled: true).environment(\.locale, Locale(identifier: "de"))
}
#endif
