import SwiftUI

/// One of the two source slots, filled or waiting.
///
/// Both variants are the same size and sit side by side, so the tray shows what a fusion is —
/// two windows, not a list that happens to have two rows. Replace and Remove moved into a menu:
/// two stacked buttons per card doubled the controls on screen for an action taken once.
struct FusionSourceCard: View {
    /// 1 or 2, shown as the slot label and used by VoiceOver to place the card.
    let index: Int
    let source: FusionSource
    let remove: () -> Void
    let replace: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 9) {
            HStack(spacing: 6) {
                Text(.fusionSlotLabel(number: index))
                    .font(.caption2.weight(.semibold)).foregroundStyle(.tertiary)
                Spacer(minLength: 4)
                menu
            }
            HStack(alignment: .top, spacing: 10) {
                FusionAppIcon(bundleIdentifier: source.candidate.bundleIdentifier, size: 30)
                VStack(alignment: .leading, spacing: 2) {
                    Text(verbatim: source.candidate.applicationName)
                        .font(.subheadline.weight(.semibold)).lineLimit(1)
                    Text(verbatim: source.title)
                        .font(.caption).foregroundStyle(.secondary).lineLimit(2)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: 0)
            }
            Spacer(minLength: 0)
            HStack(spacing: 6) {
                FusionCaptureBadge(state: source.captureState, edited: source.edited)
                if let time = source.capturedAt {
                    Text(time, format: .dateTime.hour().minute())
                        .font(.caption2).foregroundStyle(.tertiary)
                }
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, minHeight: 116, alignment: .topLeading)
        .fusionCard(emphasized: true)
        .accessibilityElement(children: .contain)
        .accessibilityLabel(Text(.fusionSlotLabel(number: index)))
        .accessibilityAction(named: Text(.fusionReplace), replace)
        .accessibilityAction(named: Text(.fusionRemove), remove)
    }

    private var menu: some View {
        Menu {
            Button(.fusionReplace, systemImage: "arrow.triangle.2.circlepath", action: replace)
            Divider()
            Button(role: .destructive, action: remove) {
                Label(.fusionRemove, systemImage: "xmark")
            }
        } label: {
            Image(systemName: "ellipsis")
        }
        .menuStyle(.borderlessButton)
        .menuIndicator(.hidden)
        .fixedSize()
        .foregroundStyle(.secondary)
        .help(Text(.fusionSourceOptions))
        .accessibilityLabel(Text(.fusionSourceOptions))
    }
}

/// The waiting half of a fusion: the same card, dashed, and it is the button that opens the picker.
struct FusionEmptySlot: View {
    let index: Int
    let choose: () -> Void

    var body: some View {
        Button(action: choose) {
            VStack(alignment: .leading, spacing: 9) {
                Text(.fusionSlotLabel(number: index))
                    .font(.caption2.weight(.semibold)).foregroundStyle(.tertiary)
                Spacer(minLength: 0)
                HStack(spacing: 10) {
                    Image(systemName: "macwindow.badge.plus")
                        .font(.system(size: 22, weight: .light)).foregroundStyle(.tint)
                        .accessibilityHidden(true)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(.fusionSlotEmptyTitle).font(.subheadline.weight(.medium))
                        Text(.fusionSlotEmptyHint).font(.caption).foregroundStyle(.secondary)
                            .lineLimit(2).fixedSize(horizontal: false, vertical: true)
                    }
                    Spacer(minLength: 0)
                }
                Spacer(minLength: 0)
            }
            .padding(12)
            .frame(maxWidth: .infinity, minHeight: 116, alignment: .topLeading)
            .contentShape(.rect)
            .background(.quaternary.opacity(0.18), in: .rect(cornerRadius: FusionMetrics.cardRadius))
            .overlay {
                RoundedRectangle(cornerRadius: FusionMetrics.cardRadius)
                    .strokeBorder(.quaternary, style: StrokeStyle(lineWidth: 1, dash: [4, 3]))
            }
        }
        .buttonStyle(FusionRowButtonStyle())
        .accessibilityLabel(Text(.fusionSlotEmptyTitle))
        .accessibilityHint(Text(.fusionSlotEmptyHint))
    }
}
