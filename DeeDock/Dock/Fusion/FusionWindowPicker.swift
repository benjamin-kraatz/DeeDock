import SwiftUI

/// The accessible window picker: every visible window, with its real icon, in one bounded list.
///
/// The list scrolls inside the step instead of growing the step body, so the footer's primary
/// action never walks off the bottom of the tray while a long list is open.
struct FusionWindowPicker: View {
    let candidates: [WindowContextCandidate]
    let chosenIDs: Set<CGWindowID>
    let disabled: Bool
    let select: (WindowContextCandidate) -> Void
    let close: () -> Void

    var body: some View {
        FusionSection(.fusionPickerTitle, symbol: "macwindow") {
            Button(.fusionClosePicker, action: close)
                .buttonStyle(.borderless).controlSize(.small)
        } content: {
            ScrollView {
                LazyVStack(spacing: 6) {
                    ForEach(candidates) { candidate in
                        row(candidate)
                    }
                }
                .padding(2)
            }
            .frame(maxHeight: 260)
            .scrollBounceBehavior(.basedOnSize)
        }
    }

    private func row(_ candidate: WindowContextCandidate) -> some View {
        let chosen = chosenIDs.contains(candidate.id)
        return Button { select(candidate) } label: {
            HStack(spacing: 10) {
                FusionAppIcon(bundleIdentifier: candidate.bundleIdentifier, size: 24)
                VStack(alignment: .leading, spacing: 2) {
                    Text(verbatim: candidate.title ?? String(localized: .applicationMenuUntitledWindow))
                        .lineLimit(1)
                    Text(verbatim: candidate.applicationName)
                        .font(.caption).foregroundStyle(.secondary).lineLimit(1)
                }
                Spacer(minLength: 8)
                if chosen {
                    Label(.fusionPickerSelected, systemImage: "checkmark.circle.fill")
                        .labelStyle(.iconOnly)
                        .foregroundStyle(.tint)
                } else {
                    Image(systemName: "plus.circle")
                        .foregroundStyle(.tertiary).accessibilityHidden(true)
                }
            }
            .padding(.horizontal, 10).padding(.vertical, 8)
            .contentShape(.rect)
            .fusionCard()
            .opacity(chosen ? 0.5 : 1)
        }
        .buttonStyle(FusionRowButtonStyle())
        .disabled(disabled || chosen)
        .accessibilityAddTraits(chosen ? .isSelected : [])
    }
}
