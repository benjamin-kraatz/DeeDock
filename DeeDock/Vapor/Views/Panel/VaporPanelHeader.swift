import SwiftUI

/// Mini orb, "Vapor", the summary ("3 folders · 1.8 GB"), and Clear.
struct VaporPanelHeader: View {
    let totals: VaporTotals
    let clear: () -> Void

    var body: some View {
        HStack(spacing: 10) {
            VaporMiniOrb()
            VStack(alignment: .leading, spacing: 1) {
                Text(.vaporTitle)
                    .font(.system(size: 15, weight: .bold))
                    .tracking(-0.15)
                Text(verbatim: VaporCopy.summary(totals))
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
                    .lineLimit(1)
                    .contentTransition(.numericText())
                    .animation(.easeOut(duration: 0.2), value: totals)
            }
            Spacer(minLength: 8)
            Button(.vaporClear, action: clear)
                .buttonStyle(VaporPillButtonStyle())
                .disabled(totals.count == 0)
        }
        .padding(EdgeInsets(top: 16, leading: 18, bottom: 10, trailing: 16))
    }
}

/// A small solid orb for the header: bright highlight up and to the left, deep blue below.
private struct VaporMiniOrb: View {
    var body: some View {
        Circle()
            .fill(RadialGradient(stops: [.init(color: .white, location: 0),
                                         .init(color: .white, location: 0.08),
                                         .init(color: Color(red: 170 / 255, green: 215 / 255, blue: 1, opacity: 0.9), location: 0.18),
                                         .init(color: Color(red: 0x3D / 255, green: 0x8B / 255, blue: 0xE6 / 255), location: 0.6),
                                         .init(color: Color(red: 0x1B / 255, green: 0x4F / 255, blue: 0xA6 / 255), location: 1)],
                                 center: UnitPoint(x: 0.35, y: 0.28), startRadius: 0, endRadius: 22))
            .overlay(Circle().strokeBorder(.white.opacity(0.5), lineWidth: 0.5))
            .frame(width: 26, height: 26)
            .accessibilityHidden(true)
    }
}
