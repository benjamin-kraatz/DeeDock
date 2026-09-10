import SwiftUI

/// Treats one dock's resting glass as a time axis of DDock-local history.
///
/// The overlay is presentation only: pointer scrubbing is mapped in `DockPanelController`
/// against the same resting surface rectangle, so this view derives its track from
/// ``DockGeometry/Layout`` rather than installing a second pointer mapper. It renders whatever
/// ``DockTimelinePresentation`` reports, which keeps previews free of a live store.
///
/// It appears only after an explicit Browse Local History command, never on hover, and absorbs
/// clicks over the dock viewport so scrubbing cannot launch the app under the pointer.
struct DockTimelineOverlay: View {
    /// Snapshot of the playhead, markers, and privacy state for this display.
    let presentation: DockTimelinePresentation
    /// Resting layout of the dock underneath. Supplies the edge and the axis length.
    let layout: DockGeometry.Layout
    /// Along-axis scroll offset of the dock contents, so the track stays over the glass.
    var scrollOffset: CGFloat = 0
    /// Leaves browsing. The coordinator restores focus from `DockTimelineController.end()`.
    let end: () -> Void
    /// Publishes the glance card's viewport bounds so the panel keeps accepting clicks inward of
    /// the glass, where Done sits. Receives `.zero` when the overlay goes away.
    var calloutRectChanged: ((CGRect) -> Void)?

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency

    private var edge: DockEdge { layout.edge }
    private var viewport: CGRect { CGRect(origin: .zero, size: layout.viewportSize) }

    /// Resting glass bounds in viewport coordinates. Magnification is suppressed while the
    /// timeline is open, so resting sizes describe exactly what is painted.
    private var track: CGRect {
        let sizes = layout.restingCenters.map { _ in layout.iconSize }
        let surface = layout.surfaceFrame(sizes: sizes)
            .offsetBy(dx: edge.isVertical ? 0 : scrollOffset, dy: edge.isVertical ? scrollOffset : 0)
        let visible = surface.intersection(viewport)
        return visible.isNull || visible.isEmpty ? surface : visible
    }

    private var axisLength: CGFloat { max(1, edge.length(of: track.size)) }

    /// Converts a 0...1 timeline position into a viewport point on the track.
    private func point(at progress: Double) -> CGPoint {
        let along = edge.along(track.origin) + CGFloat(min(1, max(0, progress))) * axisLength
        return edge.isVertical ? CGPoint(x: track.midX, y: along) : CGPoint(x: along, y: track.midY)
    }

    var body: some View {
        ZStack(alignment: .topLeading) {
            // An empty tap handler swallows clicks over the dock without moving focus, so a
            // scrub that ends over an icon cannot launch it.
            Rectangle().fill(.clear)
                .contentShape(Rectangle())
                .onTapGesture {}
                .accessibilityHidden(true)
            if !presentation.isEmpty {
                DockTimelineTrack(markers: presentation.markers, track: track, edge: edge,
                                  point: point, reduceMotion: reduceMotion)
                DockTimelinePlayhead(progress: presentation.progress, track: track, edge: edge,
                                     event: presentation.selectedEvent, point: point,
                                     reduceMotion: reduceMotion)
            }
            card
        }
        .frame(width: viewport.width, height: viewport.height, alignment: .topLeading)
        .coordinateSpace(name: Self.space)
        .accessibilityElement(children: .contain)
        .accessibilityLabel(Text(.timelineAccessibility))
    }

    @ViewBuilder private var card: some View {
        let region = layout.calloutRegion(size: layout.iconSize, length: edge.length(of: viewport.size))
        Group {
            if presentation.isEmpty {
                DockTimelineEmptyCard(recordingEnabled: presentation.recordingEnabled,
                                      reduceTransparency: reduceTransparency, end: end)
            } else if let event = presentation.selectedEvent {
                DockTimelineGlanceCard(event: event, replayEnabled: presentation.replayEnabled,
                                      reduceTransparency: reduceTransparency, end: end)
                    // Reduce Motion replaces the sliding read-out with a crossfade between events.
                    .id(reduceMotion ? event.id : nil)
                    .transition(.opacity)
                    .animation(.easeInOut(duration: 0.18), value: event.id)
            }
        }
        // Size to the text, then pin the card's center to the callout midpoint so it
        // sits over the dock. Filling the region with a leading alignment shoved it aside.
        .frame(maxWidth: min(460, max(80, region.width - 24)))
        .fixedSize(horizontal: false, vertical: true)
        .onGeometryChange(for: CGRect.self) { $0.frame(in: .named(Self.space))         } action: { rect in
            let visible = rect.intersection(viewport)
            calloutRectChanged?(visible.isNull ? .zero : visible)
        }
        .onDisappear { calloutRectChanged?(.zero) }
        .position(x: region.midX, y: region.midY)
    }

    /// Local space for reporting the card's bounds; the overlay is a sibling of the dock's own root.
    private static let space = "dockTimelineOverlay"
}

/// The time axis itself: a thin rail along the resting glass with one tick per stored event.
private struct DockTimelineTrack: View {
    let markers: [DockTimelineMarker]
    let track: CGRect
    let edge: DockEdge
    let point: (Double) -> CGPoint
    let reduceMotion: Bool

    var body: some View {
        ZStack(alignment: .topLeading) {
            Capsule()
                .fill(.secondary.opacity(0.45))
                .frame(width: edge.isVertical ? 3 : max(1, track.width - 12),
                       height: edge.isVertical ? max(1, track.height - 12) : 3)
                .position(x: track.midX, y: track.midY)
            ForEach(markers) { marker in
                Capsule()
                    .fill(tint(marker.kind))
                    .frame(width: edge.isVertical ? 12 : 3, height: edge.isVertical ? 3 : 12)
                    .position(point(marker.progress))
            }
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
        .animation(reduceMotion ? nil : .easeOut(duration: 0.15), value: markers)
    }

    private func tint(_ kind: DockLocalHistoryEvent.Kind) -> HierarchicalShapeStyle {
        kind.isRecognized ? .primary : .tertiary
    }
}

/// Marks the browsed moment on the axis and carries the VoiceOver read-out of the selection.
private struct DockTimelinePlayhead: View {
    let progress: Double
    let track: CGRect
    let edge: DockEdge
    let event: DockLocalHistoryEvent?
    let point: (Double) -> CGPoint
    let reduceMotion: Bool

    var body: some View {
        RoundedRectangle(cornerRadius: 2, style: .continuous)
            .fill(.tint)
            .frame(width: edge.isVertical ? max(8, track.width - 8) : 3,
                   height: edge.isVertical ? 3 : max(8, track.height - 8))
            .shadow(radius: 2, y: 0)
            .position(point(progress))
            // Reduce Motion keeps the playhead from sliding; it jumps to the selected event.
            .animation(reduceMotion ? nil : .snappy(duration: 0.16), value: progress)
            .allowsHitTesting(false)
            .accessibilityElement()
            .accessibilityLabel(Text(.timelinePlayhead))
            .accessibilityValue(event.map { Text($0.glanceTitle) } ?? Text(.timelineEmptyTitle))
    }
}

/// Read-out for the browsed event, sized to stay legible while the pointer keeps moving.
private struct DockTimelineGlanceCard: View {
    let event: DockLocalHistoryEvent
    let replayEnabled: Bool
    let reduceTransparency: Bool
    let end: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            HStack(alignment: .firstTextBaseline, spacing: 10) {
                Text(event.glanceTitle)
                    .font(.callout.weight(.semibold))
                    .lineLimit(2)
                    .contentTransition(.numericText())
                    .animation(.default, value: event.glanceTitle)

                Spacer(minLength: 8)
                Button(.timelineClose, systemImage: "xmark", action: end)
                    .font(.caption)
                    .buttonStyle(.plain)
                    .controlSize(.small)
                    .labelStyle(.iconOnly)
                    .padding(.vertical, 4)
                    .padding(.horizontal, 2)
                    .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 69))
                    .glassEffect()
            }
            Text(event.occurredAt, format: .relative(presentation: .named))
                .font(.caption)
                .foregroundStyle(.secondary)
                .contentTransition(.numericText())
                .animation(.default, value: event.occurredAt)
            Text(replayEnabled ? .timelineReplayHint : .timelineScrubHint)
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
        .modifier(DockTimelineCardChrome(reduceTransparency: reduceTransparency))
    }
}

/// Privacy-first state for a dock with nothing to scrub, including paused recording.
private struct DockTimelineEmptyCard: View {
    let recordingEnabled: Bool
    let reduceTransparency: Bool
    let end: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(alignment: .firstTextBaseline, spacing: 10) {
                Text(.timelineEmptyTitle)
                    .font(.callout.weight(.semibold))
                Spacer(minLength: 8)
                Button(.timelineClose, action: end)
                    .controlSize(.small)
            }
            Text(recordingEnabled ? .timelineEmptyMessage : .timelineEmptyRecordingOff)
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .modifier(DockTimelineCardChrome(reduceTransparency: reduceTransparency))
    }
}

/// Shared card surface. Reduce Transparency swaps the glass for an opaque window background.
private struct DockTimelineCardChrome: ViewModifier {
    let reduceTransparency: Bool

    @ViewBuilder func body(content: Content) -> some View {
        let shape = RoundedRectangle(cornerRadius: 12, style: .continuous)
        let card = content
            .multilineTextAlignment(.leading)
            .frame(maxWidth: 460, alignment: .leading)
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
        if reduceTransparency {
            card
                .background(shape.fill(Color(nsColor: .windowBackgroundColor)))
                .overlay(shape.strokeBorder(.primary.opacity(0.14), lineWidth: 0.5))
                .accessibilityElement(children: .contain)
        } else {
            card
                .glassEffect(.regular, in: shape)
                .overlay(shape.strokeBorder(.separator.opacity(0.4), lineWidth: 0.5))
                .accessibilityElement(children: .contain)
        }
    }
}

#if DEBUG
@MainActor
private enum DockTimelinePreviewData {
    static func layout(edge: DockEdge = .bottom, count: Int = 5) -> DockGeometry.Layout {
        var settings = DockSettings.defaults
        settings.edge = edge
        return DockGeometry.layout(count: count, favoriteCount: 3, availableLength: edge.isVertical ? 700 : 900,
                                   availableDepth: edge.isVertical ? 700 : 900, settings: settings,
                                   calloutReserve: edge.isVertical ? 260 : 168)
    }

    static var events: [DockLocalHistoryEvent] {
        let base = Date(timeIntervalSinceReferenceDate: 760_000_000)
        let samples: [(DockLocalHistoryEvent.Kind, TimeInterval, String?)] = [
            (.pinAdded, -7_200, "Sample Notes"),
            (.sessionStarted, -5_400, "Deep Work"),
            (.sessionPaused, -4_800, nil),
            (.sessionFinished, -3_600, nil),
            (.pinMoved, -1_800, "Sample Browser"),
            (.pinRemoved, -300, "Unavailable Sample"),
        ]
        return samples.enumerated().map { index, sample in
            event(sample.0, base.addingTimeInterval(sample.1), sample.2, index: index)
        }
    }

    static func presentation(progress: Double = 1,
                             events: [DockLocalHistoryEvent],
                             recordingEnabled: Bool = true,
                             replayEnabled: Bool = false) -> DockTimelinePresentation {
        DockTimelinePresentation(
            isActive: true,
            displayID: "preview",
            isEmpty: events.isEmpty,
            recordingEnabled: recordingEnabled,
            replayEnabled: replayEnabled,
            progress: progress,
            selectedEvent: DockTimelineMapping.event(at: progress, in: events),
            markers: events.map {
                DockTimelineMarker(id: $0.id, progress: DockTimelineMapping.progress(for: $0, in: events), kind: $0.kind)
            }
        )
    }

    /// Stable identifiers keep marker identity fixed across preview updates.
    private static func event(_ kind: DockLocalHistoryEvent.Kind, _ date: Date, _ subject: String?,
                              index: Int) -> DockLocalHistoryEvent {
        let id = UUID(uuidString: "00000000-0000-0000-0000-00000000000\(index % 10)") ?? UUID()
        return DockLocalHistoryEvent(id: id, occurredAt: date, kind: kind, subjectName: subject)
    }
}

/// Draws the overlay over a neutral desktop stand-in at the dock's own viewport size.
private struct DockTimelinePreviewHost: View {
    var edge: DockEdge = .bottom
    var progress: Double = 1
    var events: [DockLocalHistoryEvent] = DockTimelinePreviewData.events
    var recordingEnabled = true
    var replayEnabled = false

    var body: some View {
        let layout = DockTimelinePreviewData.layout(edge: edge)
        ZStack {
            LinearGradient(colors: [.teal.opacity(0.35), .indigo.opacity(0.5)],
                           startPoint: .topLeading, endPoint: .bottomTrailing)
            DockTimelineOverlay(
                presentation: DockTimelinePreviewData.presentation(progress: progress, events: events,
                                                                  recordingEnabled: recordingEnabled,
                                                                  replayEnabled: replayEnabled),
                layout: layout,
                end: {}
            )
        }
        .frame(width: layout.viewportSize.width, height: layout.viewportSize.height)
    }
}

#Preview("Pins and sessions, mid timeline") {
    DockTimelinePreviewHost(progress: 0.45)
}

#Preview("Pin replay enabled") {
    DockTimelinePreviewHost(progress: 0.45, replayEnabled: true)
}

#Preview("Empty and private") {
    DockTimelinePreviewHost(events: [])
}

#Preview("Recording off") {
    DockTimelinePreviewHost(events: [], recordingEnabled: false)
}

#Preview("Left edge") {
    DockTimelinePreviewHost(edge: .left, progress: 0.6)
}

#Preview("Right edge") {
    DockTimelinePreviewHost(edge: .right, progress: 0.2)
}

#Preview("Dark") {
    DockTimelinePreviewHost(progress: 0.8)
        .preferredColorScheme(.dark)
}
#endif
