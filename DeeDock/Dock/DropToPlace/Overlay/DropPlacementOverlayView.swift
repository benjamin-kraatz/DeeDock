import SwiftUI

/// One display's share of the Drop to Place overlay: outline, landing pads, and ghost.
///
/// The model holds global AppKit frames (y up). This view covers exactly `screenFrame`, also in
/// AppKit coordinates, and draws in SwiftUI's top-left space, so each frame is converted with
/// ``local(_:)``. A frame that crosses into another display is clipped here and drawn again,
/// continuously, by that display's overlay.
struct DropPlacementOverlayView: View {
    let model: DropPlacementOverlayModel
    let screenFrame: CGRect

    var body: some View {
        ZStack(alignment: .topLeading) {
            if let outline = model.outline {
                let rect = local(outline.frame)
                DropPlacementMemoryOutlineView(label: outline.label, hot: outline.hot, size: rect.size,
                                               reduceMotion: model.reduceMotion)
                    .offset(x: rect.minX, y: rect.minY)
                    .transition(.opacity)
            }
            ForEach(model.pads) { pad in
                let rect = local(pad.frame)
                DropPlacementGhostView(title: pad.title, subtitle: "", tint: pad.tint, size: rect.size, breathing: true,
                                       reduceMotion: model.reduceMotion, reduceTransparency: model.reduceTransparency)
                    .scaleEffect(pad.phase == .handoff && !model.reduceMotion ? 1.015 : 1)
                    .opacity(pad.phase == .waiting ? 1 : 0)
                    .offset(x: rect.minX, y: rect.minY)
            }
            if let ghost = model.ghost {
                let rect = local(ghost.frame)
                DropPlacementGhostView(title: ghost.title, subtitle: ghost.subtitle, tint: ghost.tint, size: rect.size,
                                       reduceMotion: model.reduceMotion, reduceTransparency: model.reduceTransparency)
                    // Size always springs (the mockup's w/h spring); position moves with the
                    // transaction, so free movement follows the pointer exactly.
                    .animation(model.reduceMotion ? nil : .spring(response: 0.28, dampingFraction: 0.74), value: rect.size)
                    .offset(x: rect.minX, y: rect.minY)
                    .transition(.opacity)
            }
        }
        .frame(width: screenFrame.width, height: screenFrame.height, alignment: .topLeading)
        .allowsHitTesting(false)
    }

    /// Global AppKit rect to this display's top-left local space.
    private func local(_ frame: CGRect) -> CGRect {
        CGRect(x: frame.minX - screenFrame.minX, y: screenFrame.maxY - frame.maxY, width: frame.width, height: frame.height)
    }
}

#Preview("Overlay · ghost over last spot") {
    let model = DropPlacementOverlayModel()
    let screen = CGRect(x: 0, y: 0, width: 1100, height: 700)
    model.outline = .init(frame: CGRect(x: 640, y: 170, width: 400, height: 430),
                          label: String(localized: .dropPlaceLastHere(when: "yesterday")), hot: true)
    model.ghost = .init(frame: CGRect(x: 640, y: 170, width: 400, height: 430),
                        title: String(localized: .dropPlaceBackWhereItWas), subtitle: "Notes",
                        tint: Color(red: 1, green: 0.85, blue: 0.29))
    model.pads = [.init(id: UUID(uuidString: "00000000-0000-0000-0000-000000000001")!, applicationID: "mail",
                        frame: CGRect(x: 60, y: 260, width: 520, height: 360),
                        title: String(localized: .dropPlaceOpening(appName: "Mail")),
                        tint: Color(red: 0.44, green: 0.69, blue: 1))]
    return DropPlacementOverlayView(model: model, screenFrame: screen)
        .background(LinearGradient(colors: [Color(red: 0.11, green: 0.09, blue: 0.22), Color(red: 0.04, green: 0.16, blue: 0.2)],
                                   startPoint: .topLeading, endPoint: .bottomTrailing))
}
