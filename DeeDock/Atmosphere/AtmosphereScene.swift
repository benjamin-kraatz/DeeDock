import AppKit
import SwiftUI
import Observation

/// Mutable scene identity survives palette changes so SwiftUI can interpolate the colors.
@MainActor @Observable
final class AtmosphereScene {
    var settings = AtmosphereSettings()
    var palette = AtmospherePalette.default
    var reduceMotion = false
    var reduceTransparency = false
    var paused = false
    var customDecor: NSImage?
    var leftEdge = true
    var rightEdge = true
    var canvasWidth: CGFloat = 1
    var offset: CGFloat = 0
}
