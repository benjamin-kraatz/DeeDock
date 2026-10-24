import AppKit
import ApplicationServices
import SwiftUI

@MainActor
final class CompanionController {
    private let model = CompanionModel()
    private let eyes = EyeModel()
    private let tracker = WindowTracker()
    private let capture = WindowCapture()
    private let agent = CompanionAgent()
    private let panel = CompanionPanel()
    private var overlay: CompanionPanel?
    private var pointerTimer: Timer?
    private var blinkTimer: Timer?
    private var sleepWork: DispatchWorkItem?
    private var shrinkWork: DispatchWorkItem?
    private var sampleTask: Task<Void, Never>?
    private var workTask: Task<Void, Never>?
    private var selection: AXSelection?
    private var enhancedPID: pid_t?
    private var menu: [String] = []
    private var hovering = false

    func start() {
        var actions = CompanionActions()
        actions.tapFace = { [weak self] in self?.tapFace() }
        actions.submit = { [weak self] in self?.submit($0) }
        actions.copy = { [weak self] in self?.copyAnswer() }
        actions.replace = { [weak self] in self?.replaceSelection() }
        actions.paste = { [weak self] in self?.pasteIntoApp() }
        actions.runProposed = { [weak self] in self?.runProposed() }
        actions.dismiss = { [weak self] in self?.dismiss() }
        let host = CompanionHostingView(rootView: CompanionRoot(model: model, eyes: eyes, actions: actions))
        host.sizingOptions = []
        host.onHover = { [weak self] inside in self?.hover(inside) }
        panel.contentView = host
        tracker.onTarget = { [weak self] target in self?.targetChanged(target) }
        tracker.onFrame = { [weak self] frame in self?.layout(frame: frame) }
        NotificationCenter.default.addObserver(forName: NSApplication.didChangeScreenParametersNotification, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.layout() }
        }
        lab("on-device model: \(agent.availability)")
        Task { [capture] in await capture.prewarm() }
        tracker.start()
        runDemoIfRequested()
    }

    /// LAB_DEMO=awake|select|prompt|answer drives the states without touching the pointer or
    /// keyboard focus, so the lab can be screenshotted while someone else uses the Mac.
    private func runDemoIfRequested() {
        guard let demo = ProcessInfo.processInfo.environment["LAB_DEMO"] else { return }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) { [self] in
            switch demo {
            case "awake": setPhase(.awake)
            case "select":
                setPhase(.selecting)
                let sheet = CompanionPanel(); sheet.level = .floating
                let view = SelectionView(); sheet.contentView = view; overlay = sheet
                layout(); sheet.orderFrontRegardless(); panel.orderFrontRegardless()
            case "prompt":
                model.context = .text("Liquid Glass adapts to the content beneath it.")
                setPhase(.prompting)
            case "focus":
                model.context = .text("demo")
                enterPrompt()
                DispatchQueue.main.asyncAfter(deadline: .now() + 2.4) { [self] in
                    lab("focus check: prompt='\(model.prompt)' panelKey=\(panel.isKeyWindow) labActive=\(NSApp.isActive) frontmost=\(NSWorkspace.shared.frontmostApplication?.localizedName ?? "?")")
                    dismiss()
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                        lab("after dismiss: labActive=\(NSApp.isActive) frontmost=\(NSWorkspace.shared.frontmostApplication?.localizedName ?? "?")")
                    }
                }
            case "answer":
                model.context = .text("Liquid Glass is a translucent material that reflects and refracts its surroundings while adapting to content.")
                submit("Translate this. If it is German, translate to English; otherwise translate to German.")
            default: break
            }
        }
    }

    // MARK: Target and geometry

    private func targetChanged(_ target: WindowTracker.Target?) {
        guard let target else {
            lab("target: none")
            panel.orderOut(nil)
            return
        }
        lab("target: \(target.appName) wid=\(target.windowID) frame=\(target.frame.integral) fullScreen=\(target.isFullScreen)")
        if [.selecting, .prompting, .thinking, .answered].contains(model.phase) { dismiss() }
        model.appName = target.appName
        layout()
        panel.orderFrontRegardless()
        sampleColor()
    }

    /// AppKit's global space is bottom-left based on the primary display; AX/CG frames are top-left.
    private func layout(frame override: CGRect? = nil) {
        guard var target = tracker.target else { return }
        if let override { target.frame = override }
        let primaryHeight = NSScreen.screens.first?.frame.height ?? 0
        let windowTop = primaryHeight - target.frame.minY
        let screen = NSScreen.screens.first { $0.frame.contains(NSPoint(x: target.frame.midX, y: windowTop - 1)) } ?? NSScreen.main
        let roomAbove = (screen?.visibleFrame.maxY ?? .greatestFiniteMagnitude) - windowTop
        let placement: CompanionModel.Placement = target.isFullScreen || roomAbove < Layout.tabHeight ? .inside : .above
        if placement != model.placement { model.placement = placement }
        let size = model.panelSize
        let x = (target.frame.midX - size.width / 2).rounded()
        let top = placement == .above ? windowTop - 1 + Layout.tabHeight + Layout.shadowMargin : windowTop
        panel.setFrame(NSRect(x: x, y: top - size.height, width: size.width, height: size.height), display: true)
        overlay?.setFrame(NSRect(x: target.frame.minX, y: windowTop - target.frame.height,
                                 width: target.frame.width, height: target.frame.height), display: true)
    }

    private func resize(growing: Bool) {
        shrinkWork?.cancel()
        if growing { layout(); return }
        let work = DispatchWorkItem { [weak self] in self?.layout() }
        shrinkWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.45, execute: work)
    }

    private func setPhase(_ phase: CompanionModel.Phase) {
        if phase != model.phase { lab("phase → \(phase)") }
        let grows = phaseSize(phase).width >= panel.frame.width || phaseSize(phase).height >= panel.frame.height
        if grows { model.phase = phase; resize(growing: true) } else { model.phase = phase; resize(growing: false) }
        updatePointerTracking()
    }

    private func phaseSize(_ phase: CompanionModel.Phase) -> CGSize {
        let current = model.phase
        model.phase = phase
        defer { model.phase = current }
        return model.panelSize
    }

    private func sampleColor() {
        guard let target = tracker.target else { return }
        sampleTask?.cancel()
        let half = model.tabWidth / 2
        let range = max(0, target.frame.width / 2 - half)...(target.frame.width / 2 + half)
        let started = Date()
        sampleTask = Task { [weak self] in
            guard let color = await self?.capture.titlebarColor(windowID: target.windowID, xRange: range), !Task.isCancelled,
                  let self, self.tracker.target?.windowID == target.windowID else { return }
            let rgb = color.usingColorSpace(.sRGB) ?? color
            let luminance = 0.2126 * rgb.redComponent + 0.7152 * rgb.greenComponent + 0.0722 * rgb.blueComponent
            self.model.tint = Color(nsColor: rgb)
            self.model.tintIsDark = luminance < 0.5
            lab(String(format: "tint #%02X%02X%02X sampled in %.0fms", Int(rgb.redComponent * 255), Int(rgb.greenComponent * 255),
                       Int(rgb.blueComponent * 255), Date().timeIntervalSince(started) * 1000))
        }
    }

    // MARK: Hover, eyes, blink

    private func hover(_ inside: Bool) {
        hovering = inside
        sleepWork?.cancel()
        if inside, model.phase == .idle {
            setPhase(.awake)
            sampleColor()
        } else if !inside, model.phase == .awake {
            let work = DispatchWorkItem { [weak self] in
                guard let self, self.model.phase == .awake, !self.hovering else { return }
                self.setPhase(.idle)
            }
            sleepWork = work
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.6, execute: work)
        }
    }

    /// Eyes only move while the companion is awake; idle costs no timers at all.
    private func updatePointerTracking() {
        if model.phase == .idle {
            pointerTimer?.invalidate(); pointerTimer = nil
            blinkTimer?.invalidate(); blinkTimer = nil
            eyes.pupil = CGSize(width: 0, height: 2)
            return
        }
        if pointerTimer == nil {
            pointerTimer = Timer.scheduledTimer(withTimeInterval: 1.0 / 60, repeats: true) { _ in
                MainActor.assumeIsolated { [weak self] in self?.updatePupils() }
            }
            RunLoop.main.add(pointerTimer!, forMode: .common)
        }
        if blinkTimer == nil {
            blinkTimer = Timer.scheduledTimer(withTimeInterval: 3.4, repeats: true) { _ in
                MainActor.assumeIsolated { [weak self] in
                    self?.eyes.blink = true
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.12) { self?.eyes.blink = false }
                }
            }
        }
    }

    private func updatePupils() {
        let mouse = NSEvent.mouseLocation
        let frame = panel.frame
        let faceX = model.isBar ? frame.minX + Layout.shadowMargin + Layout.flare + 7 + 20 : frame.midX
        let tabTop = model.placement == .above ? frame.maxY - Layout.shadowMargin : frame.maxY
        let face = CGPoint(x: faceX, y: tabTop - Layout.tabHeight / 2)
        let dx = mouse.x - face.x, dy = mouse.y - face.y
        let distance = max(1, hypot(dx, dy))
        let reach = min(1, distance / 140)
        let next = CGSize(width: dx / distance * 2.6 * reach, height: -dy / distance * 2.2 * reach)
        if abs(next.width - eyes.pupil.width) > 0.05 || abs(next.height - eyes.pupil.height) > 0.05 { eyes.pupil = next }
    }

    // MARK: Selection mode

    private func tapFace() {
        switch model.phase {
        case .idle, .awake: beginSelection()
        case .selecting: takeWholeWindow()
        default: dismiss()
        }
    }

    private func beginSelection() {
        guard let target = tracker.target else { return }
        tracker.isPinned = true
        loadMenu(pid: target.pid)
        let started = Date()
        if let found = ContextReader.selection(pid: target.pid) {
            lab("AX selection: \(found.text.count) chars, replaceable=\(found.replaceable) in \(Int(Date().timeIntervalSince(started) * 1000))ms")
            selection = found
            model.canReplace = found.replaceable
            model.context = .text(found.text)
            enterPrompt()
            return
        }
        lab("AX selection: none (\(Int(Date().timeIntervalSince(started) * 1000))ms) → selection overlay")
        setPhase(.selecting)
        showOverlay()
    }

    private func showOverlay() {
        let sheet = CompanionPanel()
        sheet.allowsKey = true
        sheet.level = .floating
        let view = SelectionView()
        view.onRegion = { [weak self] rect in self?.takeRegion(rect) }
        view.onWhole = { [weak self] in self?.takeWholeWindow() }
        view.onCancel = { [weak self] in self?.dismiss() }
        sheet.contentView = view
        overlay = sheet
        layout()
        sheet.orderFrontRegardless()
        sheet.makeKey()
        sheet.makeFirstResponder(view)
        panel.orderFrontRegardless()
        lab("overlay key=\(sheet.isKeyWindow) frontmost=\(NSWorkspace.shared.frontmostApplication?.localizedName ?? "?")")
    }

    private func closeOverlay() {
        overlay?.orderOut(nil)
        overlay = nil
    }

    private func takeRegion(_ rect: CGRect) {
        guard let target = tracker.target else { return }
        closeOverlay()
        model.context = nil
        enterPrompt()
        model.busyLabel = "Reading region…"
        workTask = Task { [weak self] in
            guard let self else { return }
            let started = Date()
            guard let image = await self.capture.image(windowID: target.windowID, rect: rect) else { lab("region capture failed"); return }
            let text = await self.capture.recognizeText(image)
            lab("region \(rect.integral): \(image.width)x\(image.height) px, OCR \(text.count) chars in \(Int(Date().timeIntervalSince(started) * 1000))ms")
            self.model.context = .region(image, recognized: text)
        }
    }

    private func takeWholeWindow() {
        guard let target = tracker.target else { return }
        closeOverlay()
        model.context = nil
        enterPrompt()
        workTask = Task { [weak self] in
            guard let self else { return }
            let started = Date()
            var axText = ""
            if let element = self.tracker.targetElement {
                if ContextReader.wakeWebAccessibility(pid: target.pid) { self.enhancedPID = target.pid; try? await Task.sleep(for: .milliseconds(600)) }
                axText = ContextReader.windowText(element)
            }
            let axTime = Int(Date().timeIntervalSince(started) * 1000)
            let image = await self.capture.image(windowID: target.windowID)
            var text = axText
            var source = "accessibility"
            if axText.count < 200, let image {
                text = await self.capture.recognizeText(image)
                source = "OCR"
            }
            lab("window: AX \(axText.count) chars in \(axTime)ms; used \(source) (\(text.count) chars); total \(Int(Date().timeIntervalSince(started) * 1000))ms")
            self.model.context = .window(image, text: text, source: source)
        }
    }

    private func enterPrompt() {
        model.prompt = ""
        model.answer = ""
        model.proposedAction = nil
        model.toast = nil
        setPhase(.prompting)
        panel.allowsKey = true
        panel.makeKey()
        lab("prompt: panel key=\(panel.isKeyWindow) frontmost=\(NSWorkspace.shared.frontmostApplication?.localizedName ?? "?")")
    }

    private func loadMenu(pid: pid_t) {
        let started = Date()
        menu = MenuCommands.list(pid: pid)
        lab("menu: \(menu.count) commands in \(Int(Date().timeIntervalSince(started) * 1000))ms")
    }

    // MARK: Agent

    private func submit(_ request: String) {
        let request = request.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !request.isEmpty, let target = tracker.target else { return }
        model.prompt = request
        model.answer = ""
        model.busyLabel = nil
        setPhase(.thinking)
        let pending = workTask
        workTask = Task { [weak self] in
            await pending?.value                       // wait for region/window context if still loading
            guard let self else { return }
            let started = Date()
            var firstToken: Date?
            do {
                try await self.agent.respond(request: request, context: self.model.context, appName: target.appName, menu: self.menu,
                                             propose: { path in Task { @MainActor [weak self] in self?.model.proposedAction = path } },
                                             update: { [weak self] text in
                                                 if firstToken == nil { firstToken = Date() }
                                                 self?.model.answer = text
                                             })
                lab("answer: first token \(Int((firstToken ?? Date()).timeIntervalSince(started) * 1000))ms, total \(Int(Date().timeIntervalSince(started) * 1000))ms, image=\(self.model.context?.image != nil)")
            } catch {
                self.model.answer = "Couldn't answer: \(error.localizedDescription)"
                lab("answer error: \(error)")
            }
            if self.model.answer.isEmpty, self.model.proposedAction != nil { self.model.answer = "I can do that from the menu." }
            self.setPhase(.answered)
        }
    }

    // MARK: Actions back into the app

    private func copyAnswer() {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(model.answer, forType: .string)
        model.toast = "Copied"
    }

    private func replaceSelection() {
        guard let selection else { return }
        let result = AXUIElementSetAttributeValue(selection.element, kAXSelectedTextAttribute as CFString, model.answer as CFString)
        lab("replace selection → \(result.rawValue)")
        model.toast = result == .success ? "Replaced" : "Replace failed (\(result.rawValue))"
        if result == .success { DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) { [weak self] in self?.dismiss() } }
    }

    /// Clipboard + ⌘V, the route dictation tools use for apps without writable AX text (terminals, canvases).
    private func pasteIntoApp() {
        guard let target = tracker.target else { return }
        let pasteboard = NSPasteboard.general
        let saved = pasteboard.string(forType: .string)
        pasteboard.clearContents()
        pasteboard.setString(model.answer, forType: .string)
        dismiss()
        NSRunningApplication(processIdentifier: target.pid)?.activate()
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.12) {
            let source = CGEventSource(stateID: .combinedSessionState)
            for down in [true, false] {
                let event = CGEvent(keyboardEventSource: source, virtualKey: 9, keyDown: down)
                event?.flags = .maskCommand
                event?.postToPid(target.pid)
            }
            lab("pasted \(self.model.answer.count) chars into \(target.appName)")
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.8) {
                guard let saved else { return }
                pasteboard.clearContents()
                pasteboard.setString(saved, forType: .string)
            }
        }
    }

    private func runProposed() {
        guard let path = model.proposedAction, let target = tracker.target else { return }
        let ok = MenuCommands.press(pid: target.pid, path: path)
        lab("menu press \(path) → \(ok)")
        model.toast = ok ? "Done" : "Couldn't find \(path)"
        if ok { DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) { [weak self] in self?.dismiss() } }
    }

    private func dismiss() {
        workTask?.cancel()
        closeOverlay()
        if let pid = enhancedPID { ContextReader.restoreEnhancedUserInterface(pid: pid); enhancedPID = nil }
        panel.allowsKey = false
        if panel.isKeyWindow { panel.resignKey() }
        selection = nil
        model.context = nil
        model.canReplace = false
        tracker.isPinned = false
        setPhase(hovering ? .awake : .idle)
        tracker.refresh()
    }
}
