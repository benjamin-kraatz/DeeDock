import Foundation
import Testing

@MainActor
struct DockSettingsGeometryTests {
    @Test("Position reference selects the usable desktop or the actual screen edge")
    func referenceAndDistance() {
        let screen = CGRect(x: -1920, y: -360, width: 1920, height: 1080)
        let visible = CGRect(x: -1920, y: -280, width: 1920, height: 970)
        for reference in DockSettings.PositionReference.allCases {
            var settings = DockSettings.defaults
            settings.positionReference = reference
            settings.bottomDistance = 0
            let frame = DockGeometry.referenceFrame(screenFrame: screen, visibleFrame: visible, settings: settings)
            #expect(frame == (reference == .usableDesktop ? visible : screen))
            let layout = DockGeometry.layout(count: 5, favoriteCount: 3, availableWidth: frame.width, settings: settings)
            let panel = DockGeometry.panelFrame(referenceFrame: frame, layout: layout, settings: settings)
            #expect(panel.minY + DockGeometry.bottomMargin == frame.minY)
            #expect(panel.midX == frame.midX)
        }
    }

    @Test("Alignment and extreme offsets keep the envelope accessible without changing preferences")
    func alignmentAndClamping() {
        let reference = CGRect(x: -1280, y: -180, width: 1280, height: 720)
        let layout = DockGeometry.layout(count: 5, favoriteCount: 3, availableWidth: reference.width)
        var settings = DockSettings.defaults
        let center = DockGeometry.panelFrame(referenceFrame: reference, layout: layout, settings: settings)
        settings.horizontalOffset = 40
        #expect(DockGeometry.panelFrame(referenceFrame: reference, layout: layout, settings: settings).minX == center.minX + 40)
        for alignment in DockSettings.Alignment.allCases {
            for offset: Double in [-1000, 0, 1000] {
                settings.alignment = alignment
                settings.horizontalOffset = offset
                settings.bottomDistance = 300
                let before = settings
                let panel = DockGeometry.panelFrame(referenceFrame: reference, layout: layout, settings: settings)
                #expect(panel.minX >= reference.minX)
                #expect(panel.maxX <= reference.maxX)
                #expect(panel.maxY <= reference.maxY)
                #expect(settings == before)
            }
        }
        settings = .defaults
        settings.alignment = .left
        #expect(DockGeometry.panelFrame(referenceFrame: reference, layout: layout, settings: settings).midX < center.midX)
        settings.alignment = .right
        #expect(DockGeometry.panelFrame(referenceFrame: reference, layout: layout, settings: settings).midX > center.midX)
    }

    @Test("Largest icons fit their hover envelope and keep glass height fixed")
    func maximumSize() {
        var settings = DockSettings.defaults
        settings.iconSize = 96
        settings.magnification = 2
        let layout = DockGeometry.layout(count: 5, favoriteCount: 3, availableWidth: 2000, settings: settings)
        #expect(layout.iconSize == 96)
        let resting = layout.sizes(pointerX: nil, reduceMotion: false)
        for pointer in layout.restingCenters {
            let sizes = layout.sizes(pointerX: pointer, reduceMotion: false)
            #expect(sizes.max() == 192)
            #expect(layout.contentWidth(sizes: sizes) <= layout.canvasWidth)
            #expect(layout.surfaceFrame(sizes: sizes).height == layout.surfaceFrame(sizes: resting).height)
            let frame = layout.buttonFrame(centerX: 0, size: 192)
            #expect(frame.minY >= 64) // Keep room for the hover label above the largest button.
            #expect(frame.maxY == layout.buttonFrame(centerX: 0, size: 96).maxY)
        }
        #expect(layout.sizes(pointerX: layout.restingCenters[0], reduceMotion: true) == resting)
        settings.magnification = 1
        let disabled = DockGeometry.layout(count: 5, favoriteCount: 3, availableWidth: 2000, settings: settings)
        #expect(disabled.sizes(pointerX: disabled.restingCenters[0], reduceMotion: false).allSatisfy { $0 == 96 })
        let crowded = DockGeometry.layout(count: 40, favoriteCount: 3, availableWidth: 560, settings: settings)
        #expect(crowded.iconSize == 32)
        #expect(crowded.canvasWidth > crowded.viewportWidth)
        #expect(settings.iconSize == 96)
    }
}
