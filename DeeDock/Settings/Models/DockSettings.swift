import Foundation

/// Requested preferences; fitting a dock to a display never mutates these values.
struct DockSettings: Codable, Equatable {
    /// Physical along-edge anchor, independent of interface reading direction.
    enum Alignment: String, Codable, CaseIterable { case start = "left", center, end = "right" }
    /// Screen geometry used to measure placement; usableDesktop respects reserved system UI.
    enum PositionReference: String, Codable, CaseIterable {
        case usableDesktop, screenEdge

        /// Top placement uses reserved desktop bounds without overwriting the saved request.
        func resolved(for edge: DockEdge) -> Self { edge == .top ? .usableDesktop : self }
    }

    /// Marker for running applications, independent of keyboard selection and foreground activity.
    enum RunningIndicatorStyle: String, Codable, CaseIterable {
        case dot, bar, square, targetLock, orbit, stardust, powerBadge, glitch,
             plasma, hologram, solarFlare, prism, lavaChrome, singularity, hidden

        /// Withdrawn styles, mapped to their nearest survivor. A saved preference naming one
        /// must keep working: rejecting it would fail the whole settings document, not just
        /// this field. Genuinely unknown values still throw.
        private static let retired: [String: Self] = ["neon": .plasma, "aura": .solarFlare]

        init(from decoder: Decoder) throws {
            let container = try decoder.singleValueContainer()
            let raw = try container.decode(String.self)
            guard let value = Self(rawValue: raw) ?? Self.retired[raw] else {
                throw DecodingError.dataCorruptedError(in: container,
                    debugDescription: "Unknown running indicator style \(raw)")
            }
            self = value
        }
    }

    /// Layers affected by idle dimming. Labels and interaction feedback remain fully readable.
    enum FadeTarget: String, Codable, CaseIterable {
        case entireDock, backgroundOnly, iconsOnly
    }

    /// Requested resting size in points; the display may require a smaller effective size.
    var iconSize: Double = 48
    /// Maximum hover scale; 1 disables magnification.
    var magnification: Double = 1.4
    /// Gap between adjacent Dock items in logical points.
    var itemSpacing: Double = 4
    var appVisibility: DockAppVisibility = .showAll
    /// Whether each display dock includes the trailing system Trash tile.
    var showTrash: Bool = true
    /// Whether Empty Trash requires DeeDock's destructive confirmation alert.
    var confirmBeforeEmptyingTrash: Bool = true
    /// Whether hovering a running app can present its windows.
    var windowPeekEnabled: Bool = true
    var windowPeekSize: WindowPeekSize = .medium
    var windowPeekLayout: WindowPeekLayout = .grid
    var windowPeekStyle: WindowPeekStyle = .glass
    var windowPeekIncludeMinimized: Bool = true
    var windowPeekIncludeUntitled: Bool = true
    /// Seconds a pointer must remain over an app before Peek opens.
    var windowPeekHoverDelay: Double = 0.4
    var tooltipPreset: DockTooltipPreset = .classic
    var runningIndicatorStyle: RunningIndicatorStyle = .dot
    /// Whether the shader indicator styles animate. The drawn styles are always still, and
    /// Reduce Motion overrides this without rewriting the saved preference.
    var animateIndicators: Bool = true
    var edge: DockEdge = .bottom
    var alignment: Alignment = .center
    /// Signed displacement from the alignment anchor, in points; positive moves right on horizontal docks and down on side docks.
    var alongEdgeOffset: Double = 0
    /// Distance in points from the chosen reference edge to the glass outer edge.
    var edgeDistance: Double = 8
    var positionReference: PositionReference = .usableDesktop

    /// Hiding the material retains its opacity preference and the dock geometry.
    var showBackground: Bool = true
    /// Legacy preference retained for round trips; native glass ignores steady-state opacity.
    var backgroundOpacity: Double = 100
    var fadeWhenIdle: Bool = false
    var fadeTarget: DockSettings.FadeTarget = .entireDock
    /// Percentage of normal artwork opacity retained after the idle delay.
    var idleOpacity: Double = 40
    /// Seconds without dock interaction, snapped to one-second steps.
    var idleDelay: Double = 3
    var fadeOutDuration: Double = 0.3
    var restoreDuration: Double = 0.1

    var behavior = DockBehaviorSettings()

    static let defaults = DockSettings()

    /// Rejects malformed persisted or transient input before it can enter geometry calculations.
    var isValid: Bool {
        (0...100).contains(backgroundOpacity) && (0...100).contains(idleOpacity)
            && (0...30).contains(idleDelay) && (0...2).contains(fadeOutDuration)
            && (0...0.5).contains(restoreDuration)
            && [backgroundOpacity, idleOpacity, idleDelay, fadeOutDuration, restoreDuration].allSatisfy(\.isFinite)
            && behavior.isValid && (32...96).contains(iconSize) && (1...2).contains(magnification)
            && (0...24).contains(itemSpacing)
            && (0.2...1).contains(windowPeekHoverDelay)
            && (-1000...1000).contains(alongEdgeOffset) && (0...300).contains(edgeDistance)
            && [iconSize, magnification, itemSpacing, windowPeekHoverDelay, alongEdgeOffset, edgeDistance].allSatisfy(\.isFinite)
    }

    /// Snaps valid values to the controls' precision. Invalid values have no normalized result.
    var normalized: DockSettings? {
        guard isValid else { return nil }
        var result = self
        result.backgroundOpacity = (backgroundOpacity / 10).rounded() * 10
        result.idleOpacity = (idleOpacity / 5).rounded() * 5
        result.idleDelay = idleDelay.rounded()
        result.fadeOutDuration = (fadeOutDuration * 20).rounded() / 20
        result.restoreDuration = (restoreDuration * 20).rounded() / 20
        result.behavior = behavior.normalized!
        result.iconSize = iconSize.rounded()
        result.magnification = (magnification * 20).rounded() / 20
        result.itemSpacing = itemSpacing.rounded()
        result.windowPeekHoverDelay = (windowPeekHoverDelay * 10).rounded() / 10
        result.alongEdgeOffset = alongEdgeOffset.rounded()
        result.edgeDistance = edgeDistance.rounded()
        return result
    }
}


extension DockSettings {
    private enum CodingKeys: String, CodingKey {
        case showBackground, backgroundOpacity, fadeWhenIdle, fadeTarget, idleOpacity, idleDelay, fadeOutDuration, restoreDuration
        case appVisibility, showTrash, confirmBeforeEmptyingTrash, tooltipPreset
        case windowPeekEnabled, windowPeekSize, windowPeekLayout, windowPeekStyle
        case windowPeekIncludeMinimized, windowPeekIncludeUntitled, windowPeekHoverDelay
        case iconSize, magnification, itemSpacing, runningIndicatorStyle, animateIndicators, edge, alignment, positionReference, behavior
        case alongEdgeOffset = "horizontalOffset"
        case edgeDistance = "bottomDistance"
    }

    /// Only an absent new key receives defaults. Existing required keys and malformed values still throw.
    init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        showBackground = values.contains(.showBackground) ? try values.decode(Bool.self, forKey: .showBackground) : true
        backgroundOpacity = values.contains(.backgroundOpacity) ? try values.decode(Double.self, forKey: .backgroundOpacity) : 100
        fadeWhenIdle = values.contains(.fadeWhenIdle) ? try values.decode(Bool.self, forKey: .fadeWhenIdle) : false
        fadeTarget = values.contains(.fadeTarget) ? try values.decode(DockSettings.FadeTarget.self, forKey: .fadeTarget) : .entireDock
        idleOpacity = values.contains(.idleOpacity) ? try values.decode(Double.self, forKey: .idleOpacity) : 40
        idleDelay = values.contains(.idleDelay) ? try values.decode(Double.self, forKey: .idleDelay) : 3
        fadeOutDuration = values.contains(.fadeOutDuration) ? try values.decode(Double.self, forKey: .fadeOutDuration) : 0.3
        restoreDuration = values.contains(.restoreDuration) ? try values.decode(Double.self, forKey: .restoreDuration) : 0.1
        appVisibility = values.contains(.appVisibility) ? try values.decode(DockAppVisibility.self, forKey: .appVisibility) : .showAll
        showTrash = values.contains(.showTrash) ? try values.decode(Bool.self, forKey: .showTrash) : true
        confirmBeforeEmptyingTrash = values.contains(.confirmBeforeEmptyingTrash)
            ? try values.decode(Bool.self, forKey: .confirmBeforeEmptyingTrash) : true
        windowPeekEnabled = try values.decodeIfPresent(Bool.self, forKey: .windowPeekEnabled) ?? true
        windowPeekSize = try values.decodeIfPresent(WindowPeekSize.self, forKey: .windowPeekSize) ?? .medium
        windowPeekLayout = try values.decodeIfPresent(WindowPeekLayout.self, forKey: .windowPeekLayout) ?? .grid
        windowPeekStyle = try values.decodeIfPresent(WindowPeekStyle.self, forKey: .windowPeekStyle) ?? .glass
        windowPeekIncludeMinimized = try values.decodeIfPresent(Bool.self, forKey: .windowPeekIncludeMinimized) ?? true
        windowPeekIncludeUntitled = try values.decodeIfPresent(Bool.self, forKey: .windowPeekIncludeUntitled) ?? true
        windowPeekHoverDelay = try values.decodeIfPresent(Double.self, forKey: .windowPeekHoverDelay) ?? 0.4
        tooltipPreset = values.contains(.tooltipPreset) ? try values.decode(DockTooltipPreset.self, forKey: .tooltipPreset) : .classic
        iconSize = try values.decode(Double.self, forKey: .iconSize)
        magnification = try values.decode(Double.self, forKey: .magnification)
        itemSpacing = try values.decodeIfPresent(Double.self, forKey: .itemSpacing) ?? 4
        runningIndicatorStyle = values.contains(.runningIndicatorStyle)
            ? try values.decode(RunningIndicatorStyle.self, forKey: .runningIndicatorStyle) : .dot
        animateIndicators = values.contains(.animateIndicators)
            ? try values.decode(Bool.self, forKey: .animateIndicators) : true
        edge = values.contains(.edge) ? try values.decode(DockEdge.self, forKey: .edge) : .bottom
        alignment = try values.decode(Alignment.self, forKey: .alignment)
        alongEdgeOffset = try values.decode(Double.self, forKey: .alongEdgeOffset)
        edgeDistance = try values.decode(Double.self, forKey: .edgeDistance)
        positionReference = try values.decode(PositionReference.self, forKey: .positionReference)
        behavior = values.contains(.behavior) ? try values.decode(DockBehaviorSettings.self, forKey: .behavior) : DockBehaviorSettings()
    }
}
