import SwiftUI

/// "Show caches from the open Finder folder · Turn On", while Automation isn't decided.
struct VaporFinderAccessRow: View {
    let turnOn: () -> Void

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: "folder.badge.questionmark")
                .font(.system(size: 14))
                .foregroundStyle(.secondary)
                .frame(width: 34)
                .accessibilityHidden(true)
            Text(.vaporFinderAccessPrompt)
                .font(.system(size: 12))
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 4)
            Button(.vaporTurnOn, action: turnOn)
                .buttonStyle(VaporPillButtonStyle(prominent: true))
        }
        .padding(EdgeInsets(top: 8, leading: 18, bottom: 8, trailing: 16))
        .background(VaporStyle.chip.opacity(0.6), in: .rect(cornerRadius: 13, style: .continuous))
        .padding(.horizontal, 8)
        .padding(.bottom, 6)
    }
}

/// "Drop build folders and caches here." for an empty orb.
struct VaporPanelEmptyState: View {
    var body: some View {
        VStack(spacing: 2) {
            Text(.vaporEmptyTitle)
                .font(.system(size: 13.5, weight: .semibold))
            Text(.vaporEmptyDetail)
                .font(.system(size: 12.5))
                .foregroundStyle(.secondary)
        }
        .multilineTextAlignment(.center)
        .lineSpacing(2)
        .frame(maxWidth: .infinity)
        .padding(EdgeInsets(top: 22, leading: 24, bottom: 8, trailing: 24))
    }
}

/// "Drop more folders here", a dashed well that lights up and grows while a drag hovers the panel.
struct VaporDropZone: View {
    let isTargeted: Bool

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: 13, style: .continuous)
        Text(.vaporDropMore)
            .font(.system(size: 12, weight: isTargeted ? .medium : .regular))
            .foregroundStyle(isTargeted ? AnyShapeStyle(Color.accentColor) : AnyShapeStyle(VaporStyle.faint))
            .frame(maxWidth: .infinity)
            .frame(height: isTargeted ? 52 : 42)
            .background(isTargeted ? VaporStyle.accentSoft : .clear, in: shape)
            .overlay {
                shape.strokeBorder(isTargeted ? Color.accentColor : VaporStyle.line2,
                                   style: StrokeStyle(lineWidth: 1.5, dash: [5, 4]))
            }
            .padding(EdgeInsets(top: 6, leading: 8, bottom: 2, trailing: 8))
            .animation(.spring(response: 0.25, dampingFraction: 0.75), value: isTargeted)
    }
}
