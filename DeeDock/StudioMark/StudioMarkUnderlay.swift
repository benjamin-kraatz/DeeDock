import SwiftUI

/// Decorative version mesh. It does not take clicks or appear in the accessibility tree.
///
/// Light appearance mixes about 1.5 percent black into the ink, which still reads on a near-white
/// fill. Dark appearance adds the same amount of white, which still reads on a near-black fill.
/// Either shift sits under the controls that are drawn on top of this view.
struct StudioMarkUnderlay: View {
    var payload: String
    var amplitude: Double
    @Environment(\.colorScheme) private var colorScheme

    init(payload: String = StudioMark.payload, amplitude: Double = StudioMark.amplitude) {
        self.payload = payload
        self.amplitude = amplitude
    }

    var body: some View {
        let inkWhite = colorScheme == .dark
        if let image = StudioMarkTileCache.image(payload: payload, inkWhite: inkWhite) {
            Image(decorative: image, scale: 1)
                .resizable(resizingMode: .tile)
                .interpolation(.none)
                .opacity(amplitude)
                .blendMode(inkWhite ? .plusLighter : .normal)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .allowsHitTesting(false)
                .accessibilityHidden(true)
        }
    }
}

/// One pair of tiles for the current payload. The bitmap is tiny and does not depend on window size.
@MainActor private enum StudioMarkTileCache {
    private static var payload: String?
    private static var light: CGImage?
    private static var dark: CGImage?

    static func image(payload: String, inkWhite: Bool) -> CGImage? {
        if self.payload != payload {
            self.payload = payload
            light = StudioMark.tileImage(payload: payload, inkWhite: false)
            dark = StudioMark.tileImage(payload: payload, inkWhite: true)
        }
        return inkWhite ? dark : light
    }
}

#if DEBUG
#Preview("Studio mark, boosted, light") {
    StudioMarkUnderlay(payload: "0.9.2+33", amplitude: 0.7)
        .frame(width: 460, height: 160)
        .background(Color(white: 0.94))
}
#Preview("Studio mark, boosted, dark") {
    StudioMarkUnderlay(payload: "0.9.2+33", amplitude: 0.7)
        .frame(width: 460, height: 160)
        .background(Color(white: 0.16))
        .preferredColorScheme(.dark)
}
#endif
