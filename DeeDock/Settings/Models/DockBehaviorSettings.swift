import Foundation

/// Requested auto-hide settings. Geometry fitting never changes these persisted values.
struct DockBehaviorSettings: Codable, Equatable {
    enum ActivationLocation: String, Codable, CaseIterable { case dockPosition, screenEdge }
    enum WidthMode: String, Codable, CaseIterable { case dockWidth, custom }
    var autoHide = false
    var activationLocation: ActivationLocation = .dockPosition
    var widthMode: WidthMode = .dockWidth
    var customWidth: Double = 320
    var zoneHeight: Double = 8
    var zoneOffset: Double = 0
    var revealDelay: Double = 0.10
    var hideDelay: Double = 0.40
    var animationStyle: DockAnimationStyle = .slideFade
    var animationDuration: Double = 0.20

    var isValid: Bool {
        (32...8192).contains(customWidth) && (1...64).contains(zoneHeight)
            && (-4096...4096).contains(zoneOffset) && (0...2).contains(revealDelay)
            && (0...5).contains(hideDelay) && (0...1).contains(animationDuration)
            && [customWidth, zoneHeight, zoneOffset, revealDelay, hideDelay, animationDuration].allSatisfy(\.isFinite)
    }

    var normalized: Self? {
        guard isValid else { return nil }
        var value = self
        value.customWidth = customWidth.rounded()
        value.zoneHeight = zoneHeight.rounded()
        value.zoneOffset = zoneOffset.rounded()
        value.revealDelay = (revealDelay * 20).rounded() / 20
        value.hideDelay = (hideDelay * 20).rounded() / 20
        value.animationDuration = (animationDuration * 20).rounded() / 20
        return value
    }
}
