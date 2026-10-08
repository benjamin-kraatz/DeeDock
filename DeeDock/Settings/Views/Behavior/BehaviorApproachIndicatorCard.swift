import SwiftUI

/// Settings for the edge glow that previews where a hidden dock will appear.
struct BehaviorApproachIndicatorCard: View {
    let source: SettingsValueSource
    var previewReduceMotion: Bool? = nil

    private var behavior: DockBehaviorSettings { source.value.behavior }

    var body: some View {
        SettingsCard(title: .behaviorApproachIndicator,
                     footnote: behavior.autoHide ? .behaviorApproachIndicatorHelp : .behaviorApproachIndicatorNeedsAutoHide) {
            SettingsStackedRow {
                DockApproachPreview(edge: source.value.edge, color: behavior.approachColor,
                                    active: behavior.approachIndicator && behavior.autoHide,
                                    showsGhost: behavior.approachGhost,
                                    reduceMotionOverride: previewReduceMotion)
            }
            SettingsToggleRow(title: .behaviorApproachIndicatorToggle, isOn: source.binding(\.behavior.approachIndicator))
                .settingsOverride(source.context, field: .approachIndicator)
            if behavior.approachIndicator {
                Divider().padding(.leading, SettingsMetrics.rowInset)
                SettingsPickerRow(title: .behaviorApproachColor, options: [
                    SettingsOption(value: DockBehaviorSettings.ApproachColor.automatic,
                                   title: .behaviorApproachColorAutomatic, symbol: "circle.lefthalf.filled"),
                    SettingsOption(value: .accent, title: .behaviorApproachColorAccent, symbol: "paintpalette")
                ], selection: source.binding(\.behavior.approachColor))
                    .settingsOverride(source.context, field: .approachColor)
                Divider().padding(.leading, SettingsMetrics.rowInset)
                SettingsToggleRow(title: .behaviorApproachGhostToggle, subtitle: .behaviorApproachGhostHelp,
                                  isOn: source.binding(\.behavior.approachGhost))
                    .settingsOverride(source.context, field: .approachGhost)
            }
        }
        .animation(.smooth(duration: 0.2), value: behavior.approachIndicator)
    }
}

/// A miniature screen edge: a pointer drifts toward it, the glow builds, the dock rises, and the glow fades.
/// With `showsGhost`, the mini dock's ghost materializes in the glow just before it rises.
///
/// Uses the production glow and geometry with a synthetic pointer; it never reads the real pointer
/// or wallpaper. Reduce Motion shows one still frame instead of the loop.
struct DockApproachPreview: View {
    let edge: DockEdge
    let color: DockBehaviorSettings.ApproachColor
    let active: Bool
    var showsGhost = true
    var reduceMotionOverride: Bool? = nil
    @Environment(\.accessibilityReduceMotion) private var systemReduceMotion
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    @Environment(\.colorScheme) private var colorScheme
    private var reduceMotion: Bool { reduceMotionOverride ?? systemReduceMotion }

    private static let screenSize = CGSize(width: 380, height: 190)
    private static let period = 3.6
    private static let dockDepth: CGFloat = 26
    private static let edgeGap: CGFloat = 4

    private var dockLength: CGFloat { edge.isVertical ? 110 : 170 }

    /// The mini dock's resting glass, in the preview screen's AppKit coordinates (y up).
    private var dockFrame: CGRect {
        let size = edge.size(length: dockLength, depth: Self.dockDepth), screen = Self.screenSize
        return switch edge {
        case .bottom: CGRect(x: (screen.width - size.width) / 2, y: Self.edgeGap, width: size.width, height: size.height)
        case .top: CGRect(x: (screen.width - size.width) / 2, y: screen.height - Self.edgeGap - size.height,
                          width: size.width, height: size.height)
        case .left: CGRect(x: Self.edgeGap, y: (screen.height - size.height) / 2, width: size.width, height: size.height)
        case .right: CGRect(x: screen.width - Self.edgeGap - size.width, y: (screen.height - size.height) / 2,
                            width: size.width, height: size.height)
        }
    }

    /// Blank slots stand in for icons: the preview must not read the user's real dock.
    private var ghost: DockApproachGhost? {
        guard showsGhost else { return nil }
        let glass = dockFrame, count = edge.isVertical ? 4 : 6, tile: CGFloat = 16, spacing: CGFloat = 9
        let start = (dockLength - CGFloat(count) * tile - CGFloat(count - 1) * spacing) / 2
        let inset = (Self.dockDepth - tile) / 2
        let tiles = (0..<count).map { index in
            let along = start + CGFloat(index) * (tile + spacing)
            let frame = edge.isVertical ? CGRect(x: glass.minX + inset, y: glass.minY + along, width: tile, height: tile)
                : CGRect(x: glass.minX + along, y: glass.minY + inset, width: tile, height: tile)
            return DockApproachGhost.Tile(frame: frame, icon: nil)
        }
        return DockApproachGhost(glass: glass, cornerRadius: 8, tiles: tiles)
    }

    private var geometry: DockApproachGeometry {
        let screen = CGRect(origin: .zero, size: Self.screenSize)
        let length: CGFloat = edge.isVertical ? 110 : 170, depth: CGFloat = 6
        let zone: CGRect = switch edge {
        case .bottom: CGRect(x: screen.midX - length / 2, y: 0, width: length, height: depth)
        case .top: CGRect(x: screen.midX - length / 2, y: screen.maxY - depth, width: length, height: depth)
        case .left: CGRect(x: 0, y: screen.midY - length / 2, width: depth, height: length)
        case .right: CGRect(x: screen.maxX - depth, y: screen.midY - length / 2, width: depth, height: length)
        }
        return DockApproachGeometry(screen: screen, zone: zone, edge: edge, ghost: ghost?.bounds)
    }

    private var tone: DockApproachTone {
        color == .accent ? .accent : .automatic(luminance: colorScheme == .dark ? 0.2 : 0.8, darkAppearance: colorScheme == .dark)
    }

    var body: some View {
        Group {
            if reduceMotion || !active {
                frame(at: 0.55)
            } else {
                TimelineView(.animation) { context in
                    frame(at: context.date.timeIntervalSinceReferenceDate.truncatingRemainder(dividingBy: Self.period) / Self.period)
                }
            }
        }
        .frame(width: Self.screenSize.width, height: Self.screenSize.height)
        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
        .overlay { RoundedRectangle(cornerRadius: 10, style: .continuous).strokeBorder(.separator) }
        .opacity(active ? 1 : 0.55)
        .frame(maxWidth: .infinity)
        .accessibilityHidden(true)
    }

    /// One moment of the loop. `t` runs 0...1: approach (0–0.55), reveal (0.55–0.8), rest.
    private func frame(at t: Double) -> some View {
        let geometry = geometry
        let approach = min(1, t / 0.55)
        let pointer = pointerLocation(progress: reduceMotion || !active ? 0.75 : approach)
        let sample = active ? geometry.sample(pointer: pointer)
            : DockApproachSample(intensity: 0, surge: 0, focus: geometry.zoneSpan.lowerBound)
        let reveal = active && !reduceMotion ? min(1, max(0, (t - 0.55) / 0.12)) : 0
        let intensity = sample.intensity * (1 - reveal)
        let local = CGRect(x: geometry.frame.minX, y: Self.screenSize.height - geometry.frame.maxY,
                           width: geometry.frame.width, height: geometry.frame.height)
        return ZStack(alignment: .topLeading) {
            LinearGradient(colors: colorScheme == .dark ? [Color(red: 0.12, green: 0.14, blue: 0.24), Color(red: 0.06, green: 0.07, blue: 0.12)]
                                                         : [Color(red: 0.86, green: 0.9, blue: 0.97), Color(red: 0.95, green: 0.93, blue: 0.9)],
                           startPoint: .top, endPoint: .bottom)
            DockApproachGlow(intensity: intensity, surge: sample.surge * (1 - reveal), focus: sample.focus, tone: tone,
                             metrics: DockApproachGlowMetrics(geometry), reduceMotion: reduceMotion,
                             reduceTransparency: reduceTransparency)
                .frame(width: local.width, height: local.height)
                .offset(x: local.minX, y: local.minY)
            if let ghost {
                DockApproachGhostLayer(amount: sample.surge * (1 - reveal), focus: sample.focus,
                                       ghost: ghost.converted(geometry.localRect), edge: edge, graphite: tone.isShadow,
                                       reduceMotion: reduceMotion, reduceTransparency: reduceTransparency)
                    .frame(width: local.width, height: local.height)
                    .offset(x: local.minX, y: local.minY)
            }
            miniDock(reveal: reveal, geometry: geometry)
            Image(systemName: "cursorarrow")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(.primary)
                .shadow(color: .black.opacity(0.25), radius: 1)
                .offset(x: pointer.x - 3, y: Self.screenSize.height - pointer.y - 2)
                .opacity(reveal > 0.5 ? 0.6 : 1)
        }
    }

    /// The synthetic pointer glides from the middle of the screen toward the zone's center.
    private func pointerLocation(progress: Double) -> CGPoint {
        let eased = 1 - pow(1 - progress, 2.2)
        let size = Self.screenSize
        let start = CGPoint(x: size.width * 0.62, y: size.height * 0.62)
        let end: CGPoint = switch edge {
        case .bottom: CGPoint(x: size.width * 0.54, y: 3)
        case .top: CGPoint(x: size.width * 0.54, y: size.height - 3)
        case .left: CGPoint(x: 3, y: size.height * 0.46)
        case .right: CGPoint(x: size.width - 3, y: size.height * 0.46)
        }
        return CGPoint(x: start.x + (end.x - start.x) * eased, y: start.y + (end.y - start.y) * eased)
    }

    private func miniDock(reveal: Double, geometry: DockApproachGeometry) -> some View {
        let rest = dockFrame, size = rest.size
        // Slides in from beyond the screen edge to its resting place; canonical +y is outward.
        let travel = edge.offset(CGSize(width: 0, height: (edge.depth(of: size) + 6) * (1 - reveal)))
        let offset = CGSize(width: rest.minX + travel.width, height: Self.screenSize.height - rest.maxY + travel.height)
        return RoundedRectangle(cornerRadius: 8, style: .continuous)
            .fill(.regularMaterial)
            .overlay { RoundedRectangle(cornerRadius: 8, style: .continuous).strokeBorder(.white.opacity(0.25)) }
            .frame(width: size.width, height: size.height)
            .offset(offset)
            .opacity(reveal)
    }
}

#if DEBUG
#Preview("Approach indicator — off and on") {
    let store = DockSettingsStore(repository: nil)
    store.update(\.behavior.autoHide, to: true)
    store.update(\.behavior.approachIndicator, to: true)
    return ScrollView {
        VStack(spacing: 20) {
            BehaviorApproachIndicatorCard(source: SettingsValueSource(store: DockSettingsStore(repository: nil), context: nil))
            BehaviorApproachIndicatorCard(source: SettingsValueSource(store: store, context: nil))
        }.padding(24)
    }.frame(width: 620, height: 760)
}
#Preview("Approach preview — edges, reduced motion stub") {
    VStack(spacing: 12) {
        DockApproachPreview(edge: .left, color: .accent, active: true, reduceMotionOverride: true)
        DockApproachPreview(edge: .top, color: .automatic, active: true, reduceMotionOverride: true)
    }.padding().preferredColorScheme(.dark)
}
#endif
