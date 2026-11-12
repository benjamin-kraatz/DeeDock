import SwiftUI

/// "Total · 1.8 GB · 104,226 files", the hold button and the note under it.
struct VaporPanelFooter: View {
    let controller: VaporController
    let folders: [VaporFolder]

    var body: some View {
        let totals = VaporTotals(folders)
        VStack(spacing: 0) {
            HStack {
                Text(.vaporTotalLabel)
                Spacer(minLength: 8)
                Text(Self.totalValue(totals))
                    .monospacedDigit()
            }
            .font(.system(size: 12))
            .foregroundStyle(.secondary)
            .padding(.bottom, 10)
            VaporHoldButton(controller: controller, count: folders.count)
            VaporFooterNote(unknownCount: folders.filter { !$0.classification.isKnown }.count)
                .padding(.top, 9)
        }
        .padding(EdgeInsets(top: 12, leading: 16, bottom: 16, trailing: 16))
        .overlay(alignment: .top) {
            Rectangle().fill(VaporStyle.line).frame(height: 0.5)
        }
        .padding(.top, 8)
    }

    /// "**1.8 GB** · 104,226 files" with the size in the primary colour, or "calculating…".
    private static func totalValue(_ totals: VaporTotals) -> AttributedString {
        guard !totals.isPending else { return AttributedString(localized: .vaporCalculating) }
        let size = VaporCopy.size(totals.bytes)
        var value = AttributedString(localized: .vaporTotalValue(size, String(localized: .vaporFileCount(totals.files))))
        if let range = value.range(of: size) {
            value[range].foregroundColor = .primary
            value[range].font = .system(size: 12, weight: .semibold).monospacedDigit()
        }
        return value
    }
}

/// "Skips the Trash…", or the unknown-folder warning when one applies.
private struct VaporFooterNote: View {
    let unknownCount: Int

    var body: some View {
        Group {
            if unknownCount > 0 {
                Text(.vaporUnknownNote(unknownCount))
                    .foregroundStyle(VaporStyle.warning)
            } else {
                Text(.vaporSkipsTrashNote)
                    .foregroundStyle(VaporStyle.faint)
            }
        }
        .font(.system(size: 11.5))
        .multilineTextAlignment(.center)
        .frame(maxWidth: .infinity)
        .fixedSize(horizontal: false, vertical: true)
    }
}
