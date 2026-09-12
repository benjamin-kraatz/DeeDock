import AppKit
import Combine
import SwiftUI

/// One cancellable playback task per visible dock. No polling, persistence, sound, or focus changes.
/// Participant frames are canvas coordinates, converted to viewport points before placement.
struct DockRumoursOverlay: View {
    let store: DockStore
    let interaction: DockInteraction
    let enabled: Bool
    let reduceTransparency: Bool

    @State private var line: Line?
    @Environment(\.locale) private var locale
    @State private var revision = 0
    @State private var suspensionReasons: Set<String> = []
    @State private var measuredSize = CGSize(width: 250, height: 56)

    private struct Request: Equatable {
        let participants: [String]
        let localeIdentifier: String
        let revision: Int
    }

    private struct Line {
        let request: Request
        let speakerID: String
        let listenerID: String
        let message: String
    }

    private var viewport: CGRect { CGRect(origin: .zero, size: interaction.layout.viewportSize) }

    private func frame(for id: String) -> CGRect? {
        guard let frame = interaction.renderedFrames[.app(id)] else { return nil }
        return frame.offsetBy(dx: interaction.layout.edge.isVertical ? 0 : interaction.scrollOffset,
                              dy: interaction.layout.edge.isVertical ? interaction.scrollOffset : 0)
    }

    private var request: Request {
        let allowed = enabled && suspensionReasons.isEmpty && interaction.exposesContent
            && interaction.sims?.isEnabled == true && interaction.sims?.aiRumoursEnabled == true
            && interaction.sims?.requiresReset == false && interaction.pointer == nil
            && !interaction.dragActive && !interaction.suppressTooltips && !store.keyboardFocus
            && store.errorMessage == nil && interaction.dragMessage == nil
            && store.focusSession?.isActive != true && store.launching.isEmpty
            && interaction.timeline?.isActive(on: store.displayID) != true
        let participants = allowed ? store.items.filter {
            $0.isFavorite && frame(for: $0.id).map { viewport.contains($0) } == true
        }.map(\.id) : []
        return Request(participants: participants.count >= 2 ? participants : [], localeIdentifier: locale.identifier, revision: revision)
    }

    var body: some View {
        let request = request
        ZStack(alignment: .topLeading) {
            if let line, line.request == request,
               let speaker = store.items.first(where: { $0.id == line.speakerID }),
               let listener = store.items.first(where: { $0.id == line.listenerID }),
               let icon = frame(for: speaker.id) {
                let layout = interaction.layout
                let region = layout.calloutRegion(size: layout.iconSize, length: layout.viewportLength)
                    .intersection(viewport)
                let placement = DockTooltipGeometry.frame(size: measuredSize, icon: icon,
                    dock: viewport, region: region, edge: layout.edge, placement: .inward)
                DockRumourBubble(speaker: speaker.reference.name, listener: listener.reference.name, message: line.message,
                    maximumWidth: min(250, max(1, region.width - 16)), reduceTransparency: reduceTransparency)
                    .onGeometryChange(for: CGSize.self) { $0.size } action: { measuredSize = $0 }
                    .frame(width: placement.width, height: placement.height)
                    .clipped()
                    .position(x: placement.midX, y: placement.midY)
            }
        }
        .frame(width: viewport.width, height: viewport.height)
        .allowsHitTesting(false)
        .transaction { $0.animation = nil }
        .task(id: request) { await play(request) }
        .onChange(of: request) { _, _ in line = nil }
        .onDisappear { line = nil }
        .onReceive(workspaceEvents) { notification in
            switch notification.name {
            case NSWorkspace.willSleepNotification: suspensionReasons.insert("sleep")
            case NSWorkspace.didWakeNotification: suspensionReasons.remove("sleep")
            case NSWorkspace.screensDidSleepNotification: suspensionReasons.insert("screens")
            case NSWorkspace.screensDidWakeNotification: suspensionReasons.remove("screens")
            case NSWorkspace.sessionDidResignActiveNotification: suspensionReasons.insert("session")
            case NSWorkspace.sessionDidBecomeActiveNotification: suspensionReasons.remove("session")
            default: break
            }
            // Space and application changes discard a conversation too. Wake never replays a backlog.
            revision += 1
        }
    }

    private var workspaceEvents: Publishers.MergeMany<NotificationCenter.Publisher> {
        let names: [Notification.Name] = [NSWorkspace.willSleepNotification, NSWorkspace.didWakeNotification,
            NSWorkspace.screensDidSleepNotification, NSWorkspace.screensDidWakeNotification,
            NSWorkspace.sessionDidResignActiveNotification, NSWorkspace.sessionDidBecomeActiveNotification,
            NSWorkspace.activeSpaceDidChangeNotification, NSWorkspace.didActivateApplicationNotification]
        return Publishers.MergeMany(names.map { NSWorkspace.shared.notificationCenter.publisher(for: $0) })
    }

    /// SwiftUI cancels the task on eligibility changes and disappearance. Every suspension point
    /// checks cancellation before publishing, so an old pair cannot speak after a pin or mode change.
    private func play(_ request: Request) async {
        line = nil
        guard request.participants.count >= 2 else { return }
        do {
            try await Task.sleep(for: .seconds(30))
            while !Task.isCancelled {
                guard let sims = interaction.sims else { return }
                let participants = store.items.filter { request.participants.contains($0.id) }.map { item in
                    DockRumourParticipant(id: item.id, name: String(item.reference.name.prefix(160)),
                        mood: sims.pinState(for: item.id, isFavorite: true)?.mood(at: .now).rawValue ?? "unknown")
                }
                guard let rumour = await sims.generateRumour(participants: participants,
                                                            locale: Locale(identifier: request.localeIdentifier)) else {
                    try Task.checkCancellation()
                    // No canned fallback or immediate retry loop. Other docks and failures skip this opportunity.
                    try await Task.sleep(for: .seconds(90))
                    continue
                }
                try Task.checkCancellation()
                guard self.request == request else { return }
                line = Line(request: request, speakerID: rumour.speakerID, listenerID: rumour.listenerID, message: rumour.opening)
                try await Task.sleep(for: .seconds(5))
                try Task.checkCancellation()
                line = Line(request: request, speakerID: rumour.listenerID, listenerID: rumour.speakerID, message: rumour.reply)
                try await Task.sleep(for: .seconds(5))
                try Task.checkCancellation()
                line = nil
                try await Task.sleep(for: .seconds(90))
            }
        } catch {
            // The request comparison hides the cancelled line immediately, before a replacement task runs.
        }
    }
}
