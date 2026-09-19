import AppKit
import SwiftUI

/// The shared toolbar keeps a real drag region separate from every actionable control.
struct AppMeltChromeBar: View {
    let pair: AppMeltPair
    let controller: AppMeltController

    var body: some View {
        HStack(spacing: 12) {
            HStack(spacing: 8) {
                windowButton(.meltClose, symbol: "xmark", color: .red) { controller.close(pair) }
                windowButton(.meltMinimize, symbol: "minus", color: .yellow) { controller.minimize(pair) }
                windowButton(.meltFit, symbol: "plus", color: .green) { controller.toggleFit(pair) }
            }
            .disabled(!pair.canChangeLayout)
            ZStack(alignment: .leading) {
                AppMeltDragRegion(began: { controller.beginDrag(pair) }, ended: { controller.endDrag(pair) }) { delta in
                    guard pair.isDragging else { return }
                    controller.layout(pair, frame: (pair.pendingFrame ?? pair.frame)
                        .offsetBy(dx: delta.width, dy: -delta.height))
                }
                Text(verbatim: pair.title).font(.headline).lineLimit(1)
                    .allowsHitTesting(false)
            }
            .frame(minWidth: 80, maxWidth: .infinity)
            .accessibilityLabel(Text(verbatim: pair.title))
            AppMeltToolbar(pair: pair, controller: controller)
        }
        .padding(.horizontal, 16)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background { AppMeltFrameRail(edge: 0) }
    }

    private func windowButton(_ title: LocalizedStringResource, symbol: String, color: Color,
                              action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol).font(.system(size: 8, weight: .bold))
                .foregroundStyle(.black.opacity(0.65))
                .frame(width: 13, height: 13).background(color, in: .circle)
        }
        .buttonStyle(.plain).help(Text(title)).accessibilityLabel(Text(title))
    }
}

/// Only the outside corners round off. Straight adjoining edges avoid gaps between panels.
struct AppMeltFrameRail: View {
    let edge: Int
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency

    var body: some View {
        let radius = AppMeltGeometry.cornerRadius
        let shape = UnevenRoundedRectangle(topLeadingRadius: edge == 0 ? radius : 0,
            bottomLeadingRadius: edge == 3 ? radius : 0,
            bottomTrailingRadius: edge == 3 ? radius : 0,
            topTrailingRadius: edge == 0 ? radius : 0)
        shape.fill(reduceTransparency ? AnyShapeStyle(Color(nsColor: .windowBackgroundColor))
                                     : AnyShapeStyle(.bar))
            .overlay(alignment: edge == 1 ? .leading : .trailing) {
                if edge == 1 || edge == 2 {
                    Rectangle().fill(.primary.opacity(0.12)).frame(width: 0.5)
                }
            }
            .overlay(alignment: .bottom) {
                if edge == 0 { Rectangle().fill(.primary.opacity(0.08)).frame(height: 0.5) }
            }
            .accessibilityHidden(true)
    }
}
