import SwiftUI

/// Two typed port columns. Pointer dragging and keyboard button activation create the same cable.
struct PatchBayBoard: View {
    let apps: [DockPin]
    let folders: [DockPin]
    let cables: [PatchBayCable]
    let connect: (String, String) -> Void
    @State private var selectedAppID: String?
    @State private var portFrames: [String: CGRect] = [:]
    @State private var draggingAppID: String?
    @State private var dragLocation: CGPoint?

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text(.patchBayRoutingHelp).font(.callout).foregroundStyle(.secondary)
            HStack(alignment: .top, spacing: 80) {
                VStack(alignment: .leading, spacing: 10) {
                    Text(.patchBayOutput).font(.caption.weight(.semibold))
                    ForEach(apps) { pin in
                        PatchBayPort(pin: pin, isOutput: true, selected: selectedAppID == pin.id,
                                     frameChanged: { portFrames[pin.id] = $0 }) {
                            selectedAppID = selectedAppID == pin.id ? nil : pin.id
                        }
                        .simultaneousGesture(DragGesture(minimumDistance: 8, coordinateSpace: .named("patchBay"))
                            .onChanged { value in
                                draggingAppID = pin.id
                                dragLocation = value.location
                            }
                            .onEnded { value in
                                if let folder = folders.first(where: { portFrames[$0.id]?.contains(value.location) == true }) {
                                    connect(pin.id, folder.id)
                                }
                                draggingAppID = nil
                                dragLocation = nil
                                selectedAppID = nil
                            })
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                VStack(alignment: .leading, spacing: 10) {
                    Text(.patchBayInput).font(.caption.weight(.semibold))
                    ForEach(folders) { pin in
                        PatchBayPort(pin: pin, isOutput: false, selected: false,
                                     frameChanged: { portFrames[pin.id] = $0 }) {
                            guard let selectedAppID else { return }
                            connect(selectedAppID, pin.id)
                            self.selectedAppID = nil
                        }
                        .accessibilityHint(Text(.patchBayInputHint))
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .coordinateSpace(name: "patchBay")
            .background {
                PatchBayWires(cables: cables, frames: portFrames,
                              draggingAppID: draggingAppID, dragLocation: dragLocation)
            }
            if selectedAppID != nil {
                Button(.patchBayCancelRouting) { selectedAppID = nil }
            }
        }
        .onExitCommand {
            selectedAppID = nil
            draggingAppID = nil
            dragLocation = nil
        }
        .onChange(of: apps.map(\.id) + folders.map(\.id)) {
            selectedAppID = nil
            draggingAppID = nil
            dragLocation = nil
            let currentIDs = Set(apps.map(\.id) + folders.map(\.id))
            portFrames = portFrames.filter { currentIDs.contains($0.key) }
        }
    }
}

/// Native button ports expose their full label and selected state without relying on cable color.
private struct PatchBayPort: View {
    let pin: DockPin
    let isOutput: Bool
    let selected: Bool
    let frameChanged: (CGRect) -> Void
    let activate: () -> Void

    var body: some View {
        Button(action: activate) {
            HStack(spacing: 8) {
                if !isOutput { socket }
                Image(systemName: isOutput ? "app" : "folder")
                    .accessibilityHidden(true)
                Text(verbatim: pin.name)
                    .lineLimit(2)
                    .frame(maxWidth: .infinity, alignment: .leading)
                if isOutput { socket }
            }
            .padding(10)
            .frame(minHeight: 46)
            .background(selected ? Color.accentColor.opacity(0.16) : Color(nsColor: .controlBackgroundColor),
                        in: .rect(cornerRadius: 10))
            .overlay(RoundedRectangle(cornerRadius: 10)
                .strokeBorder(selected ? Color.accentColor : Color.secondary.opacity(0.4), lineWidth: selected ? 2 : 1))
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .help(pin.name)
        .accessibilityLabel(Text(isOutput ? .patchBayOutputNamed(name: pin.name) : .patchBayInputNamed(name: pin.name)))
        .accessibilityAddTraits(selected ? [.isSelected] : [])
        .onGeometryChange(for: CGRect.self) { proxy in
            proxy.frame(in: .named("patchBay"))
        } action: { frameChanged($0) }
    }

    private var socket: some View {
        Image(systemName: selected ? "record.circle.fill" : "circle.circle")
            .foregroundStyle(.tint)
            .accessibilityHidden(true)
    }
}

/// All endpoints use the board's local point space, so scrolling and display scale do not offset cables.
private struct PatchBayWires: View {
    let cables: [PatchBayCable]
    let frames: [String: CGRect]
    let draggingAppID: String?
    let dragLocation: CGPoint?

    var body: some View {
        Canvas { context, _ in
            for cable in cables {
                guard let source = frames[cable.appID], let destination = frames[cable.folderID] else { continue }
                draw(from: CGPoint(x: source.maxX - 17, y: source.midY),
                     to: CGPoint(x: destination.minX + 17, y: destination.midY), context: context)
            }
            if let draggingAppID, let source = frames[draggingAppID], let dragLocation {
                draw(from: CGPoint(x: source.maxX - 17, y: source.midY), to: dragLocation, context: context, draft: true)
            }
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }

    private func draw(from start: CGPoint, to end: CGPoint, context: GraphicsContext, draft: Bool = false) {
        var path = Path()
        path.move(to: start)
        let bend = max(35, abs(end.x - start.x) * 0.5)
        path.addCurve(to: end, control1: CGPoint(x: start.x + bend, y: start.y),
                      control2: CGPoint(x: end.x - bend, y: end.y))
        context.stroke(path, with: .color(.accentColor), style: StrokeStyle(lineWidth: 3, lineCap: .round,
                                                                          dash: draft ? [5, 4] : []))
    }
}

#if DEBUG
#Preview("Patch bay cables") {
    let app = DockPin.application(ApplicationReference(bundleIdentifier: "com.example.editor",
                                                      url: URL(fileURLWithPath: "/Applications/Editor.app"), name: "Editor"))
    let folder = DockPin.folder(FolderReference(url: URL(fileURLWithPath: "/tmp/Project"),
                                               name: "Project", bookmarkData: Data()))
    PatchBayBoard(apps: [app], folders: [folder], cables: [
        PatchBayCable(id: UUID(), displayID: "preview", modeID: UUID(), appID: app.id,
                      folderID: folder.id, appName: app.name, folderName: folder.name)
    ], connect: { _, _ in })
    .padding(24)
    .frame(width: 620)
}
#endif
