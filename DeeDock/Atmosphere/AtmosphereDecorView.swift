import SwiftUI

/// Only these small panels accept pointer input; the ambient canvas stays click-through.
struct AtmosphereDecorView: View {
    let scene: AtmosphereScene
    @State private var lit = true
    @State private var alternate = false

    var body: some View {
        Button { lit.toggle() } label: {
            ZStack(alignment: .bottom) {
                if let image = scene.customDecor {
                    Image(nsImage: image).resizable().scaledToFit()
                        .rotationEffect(.degrees(alternate ? 15 : 0))
                        .opacity(lit ? 1 : 0.35)
                } else if scene.settings.preset == .sixtyNine {
                    HStack(alignment: .bottom, spacing: 7) {
                        candle(height: 26)
                        candle(height: 40)
                        candle(height: 22)
                    }
                } else {
                    Image(systemName: alternate ? "party.popper.fill" : "balloon.2.fill")
                        .font(.system(size: 46))
                        .foregroundStyle(scene.palette.first.color, scene.palette.second.color)
                        .opacity(lit ? 1 : 0.35)
                }
            }
            .padding(8)
            .frame(width: 84, height: 84)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(Text(.atmosphereDecorLabel))
        .accessibilityValue(Text(lit ? .atmosphereDecorOn : .atmosphereDecorOff))
        .accessibilityAction(named: Text(.atmosphereDecorAlternate)) { alternate.toggle() }
        .highPriorityGesture(LongPressGesture(minimumDuration: 0.6).onEnded { _ in alternate.toggle() })
        .opacity(scene.paused ? 0.15 : 1)
    }

    private func candle(height: CGFloat) -> some View {
        VStack(spacing: 2) {
            Ellipse().fill(alternate ? scene.palette.second.color : .orange)
                .frame(width: 8, height: 15).opacity(lit ? 1 : 0)
                .shadow(color: lit && !scene.reduceTransparency ? scene.palette.second.color : .clear, radius: 8)
            RoundedRectangle(cornerRadius: 2)
                .fill(alternate ? scene.palette.first.color : Color(red: 0.7, green: 0.4, blue: 0.25))
                .frame(width: 12, height: height)
        }
    }
}
