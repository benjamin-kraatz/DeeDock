import Foundation

/// Where the App Launcher tile sits in a dock.
///
/// `afterPin` names the pin the launcher follows, not an index, so adding or removing other pins
/// leaves it beside the same neighbor. Persisted as one string: `start`, `end`, or `afterPin:<id>`.
/// No raw value or custom description, so analytics reports only the case name, never the pin ID.
enum LauncherDockPosition: Hashable, Codable, Sendable {
    /// Before every pin, with its own divider. The default.
    case start
    /// Inside the pinned section, directly after the pin with this ID.
    case afterPin(String)
    /// After every other tile, including Trash.
    case end

    private static let afterPinPrefix = "afterPin:"

    /// The pin the launcher follows, if any.
    var anchorPinID: String? {
        if case .afterPin(let id) = self { return id }
        return nil
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        let value = try container.decode(String.self)
        switch value {
        case "start": self = .start
        case "end": self = .end
        case _ where value.hasPrefix(Self.afterPinPrefix) && value.count > Self.afterPinPrefix.count:
            self = .afterPin(String(value.dropFirst(Self.afterPinPrefix.count)))
        default:
            throw DecodingError.dataCorruptedError(in: container, debugDescription: "Unknown launcher position \(value)")
        }
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        switch self {
        case .start: try container.encode("start")
        case .end: try container.encode("end")
        case .afterPin(let id): try container.encode(Self.afterPinPrefix + id)
        }
    }

    /// The position stored before DEE-84, when the launcher could only lead or trail.
    init(legacyAtStart atStart: Bool) {
        self = atStart ? .start : .end
    }
}

/// Places the launcher tile in a projected dock and keeps its position meaningful as pins change.
///
/// Pure functions over render slots, so the store, drag previews, and tests share one rule.
enum DockLauncherPlacement {
    /// Inserts the launcher into `content`, which must not already contain it.
    ///
    /// An anchor pin that is hidden here (parked on a magnetic edge, or not on this display's list
    /// at all) falls back to the nearest earlier pin that is visible, then to `start`. A collapsed or
    /// hidden pinned section has no visible pins, so the launcher leads.
    /// - Parameter pinOrder: This display's full pin ID order, including pins not shown in `content`.
    static func entries(_ content: [DockRenderSlot], position: LauncherDockPosition, pinOrder: [String]) -> [DockRenderSlot] {
        switch position {
        case .start:
            return [.launcher] + content
        case .end:
            return content + [.launcher]
        case .afterPin(let anchor):
            guard let index = visibleAnchorIndex(anchor, in: content, pinOrder: pinOrder) else { return [.launcher] + content }
            var result = content
            result.insert(.launcher, at: index + 1)
            return result
        }
    }

    /// The slot index of `anchor`, or of the closest visible pin saved before it.
    private static func visibleAnchorIndex(_ anchor: String, in content: [DockRenderSlot], pinOrder: [String]) -> Int? {
        let visible = Dictionary(content.indices.compactMap { index in content[index].pin.map { ($0.id, index) } },
                                 uniquingKeysWith: { first, _ in first })
        if let index = visible[anchor] { return index }
        guard let saved = pinOrder.firstIndex(of: anchor) else { return nil }
        return pinOrder[..<saved].reversed().lazy.compactMap { visible[$0] }.first
    }

    /// Every place the launcher can go in `entries`, in visual order: `start`, after each visible
    /// pin, then `end`. Keyboard moves and drags step through these.
    static func stops(in entries: [DockRenderSlot]) -> [LauncherDockPosition] {
        [.start] + entries.compactMap(\.pin).map { .afterPin($0.id) } + [.end]
    }

    /// The position the launcher currently shows in `entries`, which may differ from the saved one
    /// when its anchor is hidden. Nil when the launcher is absent.
    static func renderedPosition(in entries: [DockRenderSlot]) -> LauncherDockPosition? {
        guard let index = entries.firstIndex(where: { $0.target == .launcher }) else { return nil }
        if index == 0 { return .start }
        if let pin = entries[index - 1].pin { return .afterPin(pin.id) }
        return .end
    }

    /// Keeps the launcher in place after a pin edit.
    ///
    /// When the anchor pin is removed or `relocated`, the launcher follows the pin that preceded the
    /// anchor before the edit instead of jumping with it. Returns `position` unchanged otherwise.
    /// - Parameters:
    ///   - previous: Pin IDs before the edit.
    ///   - next: Pin IDs after the edit.
    ///   - relocated: Pins the edit moved. A newly added pin can never be the anchor.
    static func reanchored(_ position: LauncherDockPosition, previous: [String], next: [String],
                           relocated: Set<String> = []) -> LauncherDockPosition {
        guard let anchor = position.anchorPinID, !next.contains(anchor) || relocated.contains(anchor),
              let index = previous.firstIndex(of: anchor) else { return position }
        let remaining = Set(next)
        let predecessor = previous[..<index].reversed().first { remaining.contains($0) && !relocated.contains($0) }
        return predecessor.map(LauncherDockPosition.afterPin) ?? .start
    }

    /// Section sizes for ``DockGeometry/layout(count:favoriteCount:utilityCount:leadingUtilityCount:availableLength:availableDepth:settings:calloutReserve:)``.
    ///
    /// A leading launcher gets its own divider, a trailing one shares the utilities' divider, and one
    /// placed after a pin joins the pinned section so no divider splits a group of pins.
    static func sectionCounts(_ slots: [DockRenderSlot]) -> (favorites: Int, utilities: Int, leading: Int) {
        let launcher = slots.firstIndex(where: \.isLauncher)
        let leading = launcher == 0 ? 1 : 0
        let amongPins = launcher.map { $0 > 0 && slots[$0 - 1].isPinned } ?? false
        // The launcher counts as a utility; only a trailing one belongs to the utility section.
        let utilities = slots.filter(\.isUtility).count - (leading == 1 || amongPins ? 1 : 0)
        return (slots.filter(\.isPinned).count + (amongPins ? 1 : 0), utilities, leading)
    }
}
