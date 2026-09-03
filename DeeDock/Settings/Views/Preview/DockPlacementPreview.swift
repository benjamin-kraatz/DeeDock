import SwiftUI

/// The same placement calculation as a live dock, drawn on a deterministic stand-in display.
struct DockPlacementPreview: View {
    var edge: DockEdge = .bottom
    let reference: DockSettings.PositionReference
    let alignment: DockSettings.Alignment
    let alongEdgeOffset: Double
    let edgeDistance: Double

    var body: some View {
        DockDisplayDiagram(settings: DockSettings(edge: edge, alignment: alignment,
            alongEdgeOffset: alongEdgeOffset, edgeDistance: edgeDistance, positionReference: reference), showsActivation: false)
    }
}

#if DEBUG
#Preview("All edges") {
    VStack {
        ForEach(DockEdge.allCases, id: \.self) { edge in
            DockPlacementPreview(edge: edge, reference: .usableDesktop, alignment: .start,
                                 alongEdgeOffset: 80, edgeDistance: 40)
        }
    }.padding()
}
#endif
