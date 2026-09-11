import AppKit
import SwiftUI

/// One stamped item: its real icon wearing the ink mark, when it was stamped, and a release
/// button that only works while the stamp is armed, matching the in-dock gesture.
struct QuarantineRecordRow: View {
    let record: QuarantineStore.Record
    let armed: Bool
    let release: () -> Void

    var body: some View {
        HStack(spacing: 10) {
            ZStack(alignment: .bottomTrailing) {
                Image(nsImage: NSWorkspace.shared.icon(forFile: record.url.path))
                    .resizable()
                    .frame(width: 28, height: 28)
                Image("QuarantineInk")
                    .resizable()
                    .frame(width: 13, height: 13)
                    .offset(x: 3, y: 3)
            }
            .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 1) {
                Text(verbatim: record.name)
                    .lineLimit(1)
                    .truncationMode(.middle)
                Text(record.stampedAt, format: .relative(presentation: .named))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .help(record.url.path)
            Spacer(minLength: SettingsMetrics.controlSpacing)
            Button(action: release) { Text(.quarantineRelease) }
                .controlSize(.small)
                .disabled(!armed)
                .help(Text(armed ? .quarantineReleaseHelp : .quarantineItemsArmHint))
        }
        .padding(.horizontal, SettingsMetrics.rowInset)
        .padding(.vertical, 8)
        .frame(maxWidth: .infinity, minHeight: SettingsMetrics.rowMinimumHeight, alignment: .leading)
    }
}

/// A sound toggle with a button to hear the sound first.
struct QuarantineSoundRow: View {
    let title: LocalizedStringResource
    @Binding var isOn: Bool
    let preview: () -> Void

    var body: some View {
        SettingsRow(title: title) {
            HStack(spacing: 10) {
                Button(action: preview) {
                    Image(systemName: "speaker.wave.2.fill")
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.borderless)
                .accessibilityLabel(Text(.quarantineSoundPreview))
                .help(Text(.quarantineSoundPreview))
                Toggle(isOn: $isOn) { Text(title) }
                    .labelsHidden()
                    .toggleStyle(.switch)
                    .controlSize(.small)
            }
        }
    }
}

/// A caption-sized inline notice for a card row.
struct QuarantineSettingsNotice: View {
    let symbol: String
    let tint: Color
    let message: Text

    var body: some View {
        Label { message } icon: { Image(systemName: symbol).foregroundStyle(tint) }
            .font(.caption)
            .fixedSize(horizontal: false, vertical: true)
            .padding(.horizontal, SettingsMetrics.rowInset)
            .padding(.vertical, 10)
            .frame(maxWidth: .infinity, alignment: .leading)
    }
}
