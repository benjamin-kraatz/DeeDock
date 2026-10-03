import SwiftUI

/// An in-place question that replaces the card's buttons, so confirming never leaves the card.
struct VolumeCardConfirmation: View {
    let symbol: String
    let title: LocalizedStringResource
    let message: LocalizedStringResource
    let confirmTitle: LocalizedStringResource
    let confirm: VolumeCardAction
    let perform: (VolumeCardAction) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label { Text(title).font(.headline) } icon: {
                Image(systemName: symbol).foregroundStyle(.orange)
            }
            Text(message)
                .font(.callout)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            HStack(spacing: 10) {
                Button { perform(.cancel) } label: { Text(.volumeCancel).frame(maxWidth: .infinity) }
                    .keyboardShortcut(.cancelAction)
                Button(role: .destructive) { perform(confirm) } label: {
                    Text(confirmTitle).frame(maxWidth: .infinity)
                }
                .keyboardShortcut(.defaultAction)
            }
            .buttonStyle(.bordered)
            .controlSize(.large)
        }
        .accessibilityElement(children: .contain)
    }
}

/// The eject in progress. The tile in the dock dims at the same time.
struct VolumeCardEjectingSection: View {
    var body: some View {
        HStack(spacing: 10) {
            ProgressView().controlSize(.small)
            Text(.volumeEjecting).font(.callout).foregroundStyle(.secondary)
            Spacer(minLength: 0)
        }
        .frame(minHeight: 32)
        .accessibilityElement(children: .combine)
    }
}

/// The farewell after a successful eject: the device can be unplugged.
struct VolumeCardFarewell: View {
    let name: String
    let reduceMotion: Bool
    @State private var appeared = false

    var body: some View {
        HStack(spacing: 14) {
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 34, weight: .semibold))
                .foregroundStyle(.white, .green)
                .scaleEffect(appeared || reduceMotion ? 1 : 0.4)
                .symbolEffect(.bounce, value: appeared)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 3) {
                Text(.volumeEjectedTitle).font(.headline)
                Text(.volumeEjectedMessage(name: name))
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
        }
        .onAppear {
            withAnimation(reduceMotion ? nil : .spring(duration: 0.45, bounce: 0.45)) { appeared = true }
        }
        .accessibilityElement(children: .combine)
    }
}
