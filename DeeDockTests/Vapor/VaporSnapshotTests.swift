import AppKit
import SwiftUI
import Testing
@testable import DeeDock

/// Renders Vapor's key views and states to PNGs for visual review against the mockup
/// (`docs/mockups/vapor-orb.html`). Opt-in: runs only when `VAPOR_SNAPSHOT_DIR` names an output
/// directory (pass `TEST_RUNNER_VAPOR_SNAPSHOT_DIR=…` to `xcodebuild test`), so normal and CI
/// runs skip it. Nothing is compared; a person looks at the images.
///
/// Rendering is offscreen with `ImageRenderer` over a desktop-like gradient. That draws shapes,
/// gradients, blurs, text and canvases faithfully, but not live effects that sample what is
/// behind a window: Liquid Glass can't be drawn, so panels and capsules use a flat translucent
/// stand-in (``EnvironmentValues/vaporGlassStandIn``) and the orb shows only its tint and
/// lighting. Scroll views are AppKit-backed and render blank, which is why the snapshots keep
/// lists short. Keyframe and timeline animations are captured at rest.
///
/// Run with `-testLanguage en` so copy matches the mockup.
@MainActor
@Suite(.enabled(if: VaporSnapshotOutput.directory != nil), .serialized)
struct VaporSnapshotTests {
    private typealias Lamp = VaporPreviewData.Lamp

    // MARK: Orb

    @Test(arguments: [ColorScheme.dark, .light])
    func orbEmpty(_ scheme: ColorScheme) throws {
        let controller = VaporPreviewData.controller()
        try snapshot("orb-empty", scheme) { VaporOrbView(controller: controller) }
    }

    @Test(arguments: [ColorScheme.dark, .light])
    func orbSettledPileLampUpperLeft(_ scheme: ColorScheme) throws {
        let controller = VaporPreviewData.controller(VaporPreviewData.pile, opensLeft: true, lamp: .upperLeft)
        try snapshot("orb-pile-lamp-upper-left", scheme) {
            VaporOrbView(controller: controller, pile: VaporPreviewData.settledPile(for: controller))
        }
    }

    @Test(arguments: [ColorScheme.dark, .light])
    func orbSettledPileLampUpperRight(_ scheme: ColorScheme) throws {
        let controller = VaporPreviewData.controller(VaporPreviewData.pile, opensLeft: false, lamp: .upperRight)
        try snapshot("orb-pile-lamp-upper-right", scheme) {
            VaporOrbView(controller: controller, pile: VaporPreviewData.settledPile(for: controller))
        }
    }

    @Test func orbDragNearby() throws {
        let controller = VaporPreviewData.controller(Array(VaporPreviewData.pile.prefix(3)))
        controller.dropHover = VaporPreviewData.nearbyDrag
        try snapshot("orb-drag-nearby", .dark) {
            VaporOrbView(controller: controller, pile: VaporPreviewData.settledPile(for: controller))
        }
    }

    @Test func orbDragOver() throws {
        let controller = VaporPreviewData.controller(Array(VaporPreviewData.pile.prefix(3)))
        controller.dropHover = VaporPreviewData.overOrbDrag
        try snapshot("orb-drag-over", .dark) {
            VaporOrbView(controller: controller, pile: VaporPreviewData.settledPile(for: controller))
        }
    }

    @Test func orbRefusalRim() throws {
        let controller = VaporPreviewData.controller(Array(VaporPreviewData.pile.prefix(2)))
        try snapshot("orb-refusal-rim", .dark) {
            ZStack {
                VaporOrbView(controller: controller, pile: VaporPreviewData.settledPile(for: controller))
                // The rim is keyframed on each refusal; drawn here at full strength.
                VaporOrbRefusalRim()
                    .frame(width: VaporGeometry.orbDiameter, height: VaporGeometry.orbDiameter)
            }
        }
    }

    @Test(arguments: [ColorScheme.dark, .light])
    func orbEvaporating(_ scheme: ColorScheme) throws {
        let controller = VaporPreviewData.controller(VaporPreviewData.pile)
        let pile = VaporPreviewData.settledPile(for: controller)
        let deletion = VaporEvent(VaporDeletion(folders: VaporPreviewData.pile, fromPanel: false))
        pile.sync(folders: VaporPreviewData.pile, addition: nil, deletion: deletion, isStaging: true, reduceMotion: false)
        var date = Date(timeIntervalSinceReferenceDate: 0)
        for _ in 0..<33 {
            date += 1.0 / 60
            _ = pile.frame(at: date)
        }
        try snapshot("orb-evaporating", scheme) {
            ZStack {
                VaporOrbView(controller: controller, pile: pile)
                VaporOrbFlash()
                    .frame(width: VaporGeometry.orbDiameter, height: VaporGeometry.orbDiameter)
                    .opacity(0.35)
            }
        }
    }

    @Test func orbReduceTransparency() throws {
        let controller = VaporPreviewData.controller(VaporPreviewData.pile, reduceTransparency: true)
        try snapshot("orb-reduce-transparency", .dark) {
            VaporOrbView(controller: controller, pile: VaporPreviewData.settledPile(for: controller))
        }
    }

    // MARK: Panel

    @Test(arguments: [ColorScheme.dark, .light])
    func panelWithFoundInAndHold(_ scheme: ColorScheme) throws {
        let controller = VaporPreviewData.controller(VaporPreviewData.panel, panel: true,
                                                     suggestions: Array(VaporPreviewData.suggestions.prefix(2)),
                                                     hold: .frozen(at: 0.5))
        try snapshot("panel-found-in-hold", scheme, size: CGSize(width: 470, height: 760)) {
            VaporPanelView(controller: controller)
        }
    }

    @Test func panelEmptyWithFinderAccessOffer() throws {
        let controller = VaporPreviewData.controller(panel: true, permission: .undetermined)
        try snapshot("panel-empty-access", .dark, size: CGSize(width: 470, height: 300)) {
            VaporPanelView(controller: controller)
        }
    }

    @Test func panelReduceTransparency() throws {
        let controller = VaporPreviewData.controller(VaporPreviewData.mixed, panel: true, reduceTransparency: true)
        try snapshot("panel-reduce-transparency", .dark, size: CGSize(width: 470, height: 520)) {
            VaporPanelView(controller: controller)
        }
    }

    @Test func sceneOrbWithOpenPanel() throws {
        let controller = VaporPreviewData.controller(VaporPreviewData.mixed, panel: true, opensLeft: true)
        let pile = VaporPreviewData.settledPile(for: controller)
        try snapshot("scene-orb-panel", .dark, size: CGSize(width: 720, height: 640)) {
            VaporSnapshotScene(orbCenter: Lamp.upperLeft.orbCenter, size: CGSize(width: 720, height: 640)) { scene in
                VaporOrbView(controller: controller, pile: pile)
                    .scenePlaced(scene, frame: VaporGeometry.orbWindowFrame(center: scene.orbCenter))
                VaporPanelView(controller: controller)
                    .fixedSize()
                    .scenePlaced(scene, frame: VaporGeometry.panelFrame(
                        orbCenter: scene.orbCenter, size: CGSize(width: VaporPanelView.width, height: 470),
                        visibleFrame: VaporPreviewData.visibleFrame), alignment: .top)
            }
        }
    }

    // MARK: Callouts

    @Test(arguments: [ColorScheme.dark, .light])
    func calloutUndo(_ scheme: ColorScheme) throws {
        let controller = VaporPreviewData.controller(
            status: VaporStatus(kind: .deleted(count: 3, failed: 0, deadline: .now.addingTimeInterval(3))))
        try snapshot("callout-undo", scheme, size: CGSize(width: 320, height: 90)) { VaporCalloutView(controller: controller) }
    }

    @Test func calloutFreed() throws {
        let controller = VaporPreviewData.controller(status: VaporStatus(kind: .freed(bytes: 1_840_000_000, count: 3, failed: 0)))
        try snapshot("callout-freed", .dark, size: CGSize(width: 320, height: 90)) { VaporCalloutView(controller: controller) }
    }

    @Test func calloutRefusal() throws {
        let controller = VaporPreviewData.controller(refusal: .standardFolder(name: "Documents"))
        try snapshot("callout-refusal", .dark, size: CGSize(width: 460, height: 90)) { VaporCalloutView(controller: controller) }
    }

    @Test func calloutTooltipAndDropToAdd() throws {
        let tooltip = VaporPreviewData.controller(VaporPreviewData.mixed)
        tooltip.isOrbHovered = true
        let drop = VaporPreviewData.controller()
        drop.dropHover = VaporPreviewData.overOrbDrag
        try snapshot("callout-tooltip-drop", .dark, size: CGSize(width: 320, height: 130)) {
            VStack(spacing: -24) {
                VaporCalloutView(controller: tooltip)
                VaporCalloutView(controller: drop)
            }
        }
    }

    // MARK: Suggestions

    @Test(arguments: [ColorScheme.dark, .light])
    func sceneSuggestions(_ scheme: ColorScheme) throws {
        let controller = VaporPreviewData.controller(VaporPreviewData.mixed, suggestions: VaporPreviewData.suggestions,
                                                     opensLeft: true)
        controller.hoveredSuggestionID = nil
        let pile = VaporPreviewData.settledPile(for: controller)
        let center = Lamp.upperLeft.orbCenter
        let layout = VaporGeometry.satelliteLayout(orbCenter: center, count: controller.bubbleSuggestions.count,
                                                   capsuleSize: VaporSuggestionsView.capsuleSize,
                                                   visibleFrame: VaporPreviewData.visibleFrame)
        try snapshot("scene-suggestions", scheme, size: CGSize(width: 640, height: 400)) {
            VaporSnapshotScene(orbCenter: center, size: CGSize(width: 640, height: 400), orbOffsetX: 170) { scene in
                VaporOrbView(controller: controller, pile: pile)
                    .scenePlaced(scene, frame: VaporGeometry.orbWindowFrame(center: center))
                VaporSuggestionsView(controller: controller, layout: layout, animatesEntrance: false)
                    .scenePlaced(scene, frame: layout.windowFrame)
            }
        }
    }

    // MARK: Rendering

    private func snapshot<Content: View>(_ name: String, _ scheme: ColorScheme, size: CGSize = CGSize(width: 260, height: 260),
                                         @ViewBuilder content: () -> Content) throws {
        let directory = try #require(VaporSnapshotOutput.directory)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let view = content()
            .frame(width: size.width, height: size.height)
            .background(VaporPreviewBackdrop())
            .environment(\.vaporGlassStandIn, true)
            .environment(\.colorScheme, scheme)
        let renderer = ImageRenderer(content: view)
        renderer.scale = 2
        var image: CGImage?
        let appearance = try #require(NSAppearance(named: scheme == .dark ? .darkAqua : .aqua))
        appearance.performAsCurrentDrawingAppearance { image = renderer.cgImage }
        let rendered = try #require(image)
        let data = try #require(NSBitmapImageRep(cgImage: rendered).representation(using: .png, properties: [:]))
        try data.write(to: directory.appendingPathComponent("\(name)-\(scheme == .dark ? "dark" : "light").png"))
    }
}

/// Where snapshots go: `VAPOR_SNAPSHOT_DIR`, or nil to skip the suite.
private enum VaporSnapshotOutput {
    nonisolated static var directory: URL? {
        ProcessInfo.processInfo.environment["VAPOR_SNAPSHOT_DIR"].map { URL(fileURLWithPath: $0, isDirectory: true) }
    }
}

/// A patch of desktop around the orb: places views whose windows have global (AppKit, y-up)
/// frames, the way ``VaporWindows`` would, inside a snapshot of `size`.
private struct VaporSnapshotScene<Content: View>: View {
    let placement: VaporScenePlacement
    let size: CGSize
    let content: (VaporScenePlacement) -> Content

    /// - Parameter orbOffsetX: How far right of the scene's centre the orb sits.
    init(orbCenter: CGPoint, size: CGSize, orbOffsetX: CGFloat = 120,
         @ViewBuilder content: @escaping (VaporScenePlacement) -> Content) {
        placement = VaporScenePlacement(orbCenter: orbCenter,
                              origin: CGPoint(x: orbCenter.x - size.width / 2 - orbOffsetX, y: orbCenter.y + size.height / 2))
        self.size = size
        self.content = content
    }

    var body: some View {
        ZStack(alignment: .topLeading) {
            content(placement)
        }
        .frame(width: size.width, height: size.height, alignment: .topLeading)
    }
}

private struct VaporScenePlacement {
    let orbCenter: CGPoint
    /// The global point shown at the scene's top-left corner.
    let origin: CGPoint
}

private extension View {
    /// Places a window's content at its global `frame` inside a snapshot scene.
    func scenePlaced(_ scene: VaporScenePlacement, frame: CGRect,
                     alignment: Alignment = .center) -> some View {
        self
            .frame(width: frame.width, height: frame.height, alignment: alignment)
            .offset(x: frame.minX - scene.origin.x, y: scene.origin.y - frame.maxY)
    }
}
