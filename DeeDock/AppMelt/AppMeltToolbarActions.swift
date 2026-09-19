import AppKit

/// One completed Fusion layout. Source identities stay fixed when their visual sides change.
struct AppMeltLayoutSnapshot {
    let frame: CGRect
    let ratio: Double
    let swapped: Bool

    init(_ pair: AppMeltPair) {
        frame = pair.frame; ratio = pair.ratio; swapped = pair.sidesSwapped
    }

    init(frame: CGRect, ratio: Double, swapped: Bool) {
        self.frame = frame; self.ratio = ratio; self.swapped = swapped
    }
}

extension AppMeltController {
    func resizeFromToolbar(_ pair: AppMeltPair, dx: CGFloat, dy: CGFloat) {
        applyToolbarLayout(pair, target: .init(frame: pair.frame.insetBy(dx: dx, dy: dy),
            ratio: pair.ratio, swapped: pair.sidesSwapped))
    }

    func moveFromToolbar(_ pair: AppMeltPair, dx: CGFloat, dy: CGFloat) {
        applyToolbarLayout(pair, target: .init(frame: pair.frame.offsetBy(dx: dx, dy: dy),
            ratio: pair.ratio, swapped: pair.sidesSwapped))
    }

    func setProportion(_ pair: AppMeltPair, ratio: Double) {
        applyToolbarLayout(pair, target: .init(frame: pair.frame, ratio: ratio, swapped: pair.sidesSwapped))
    }

    func swapSides(_ pair: AppMeltPair) {
        applyToolbarLayout(pair, target: .init(frame: pair.frame, ratio: pair.ratio, swapped: !pair.sidesSwapped))
    }

    func toggleFit(_ pair: AppMeltPair) {
        guard pair.canChangeLayout else { return }
        if let previous = pair.fittedFrom {
            applyToolbarLayout(pair, target: previous)
        } else if let display = WindowPlacementPolicy.current(pair.frame, displays: AppMeltGeometry.displays) {
            applyToolbarLayout(pair, target: .init(frame: display.usable, ratio: pair.ratio,
                swapped: pair.sidesSwapped), fitting: true)
        }
    }

    func move(_ pair: AppMeltPair, to displayID: String) {
        guard let display = AppMeltGeometry.displays.first(where: { $0.id == displayID }) else { return }
        var frame = pair.frame
        frame.size.width = min(frame.width, display.usable.width)
        frame.size.height = min(frame.height, display.usable.height)
        frame.origin = CGPoint(x: display.usable.midX - frame.width / 2, y: display.usable.midY - frame.height / 2)
        applyToolbarLayout(pair, target: .init(frame: frame, ratio: pair.ratio, swapped: pair.sidesSwapped))
    }

    func undo(_ pair: AppMeltPair) {
        guard let previous = pair.undoLayout else { return }
        applyToolbarLayout(pair, target: previous, undoing: true)
    }

    func compare(_ pair: AppMeltPair) {
        guard pair.canChangeLayout else { return }
        pair.finderTools?.dismiss()
        pair.refreshTask?.cancel()
        run(pair) { [self] in
            var windows: [ApplicationWindowSummary] = []
            for token in pair.layoutTokens { windows.append(try await service.meltSummary(token)) }
            try Task.checkCancellation()
            compareWindows?(pair, windows)
        }
    }

    /// Serializes explicit layout actions with gestures and Finder operations. Commit UI order
    /// only after both apps accept their frames; partial failures use the existing recovery flow.
    private func applyToolbarLayout(_ pair: AppMeltPair, target: AppMeltLayoutSnapshot,
                                    fitting: Bool = false, undoing: Bool = false) {
        guard pair.canChangeLayout, pairs.contains(where: { $0.id == pair.id }),
              let display = WindowPlacementPolicy.current(target.frame, displays: AppMeltGeometry.displays),
              display.usable.width >= 640, display.usable.height >= 360 else { return }
        let before = AppMeltLayoutSnapshot(pair)
        var requested = target.frame
        requested.size.width = min(requested.width, display.usable.width)
        requested.size.height = min(requested.height, display.usable.height)
        let frame = WindowPlacementPolicy.fit(requested, into: display.usable)
        guard frame.width >= 640, frame.height >= 360 else { return }
        pair.layoutPopover = false
        pair.finderTools?.invalidateLayout()
        pair.refreshTask?.cancel()
        pair.pendingFrame = nil
        run(pair) { [self] in
            // Cached translation handles belong to the previous side order.
            await service.meltEndMove(pair.sessionID)
            let tokens = target.swapped ? Array(pair.tokens.reversed()) : pair.tokens
            let accepted = try await service.meltLayout(tokens,
                frames: AppMeltGeometry.windows(in: frame, ratio: target.ratio), displays: AppMeltGeometry.displays)
            try Task.checkCancellation()
            pair.sidesSwapped = target.swapped
            pair.accept(accepted)
            pair.undoLayout = undoing ? nil : before
            pair.fittedFrom = fitting ? before : nil
            pair.chrome?.update(show: true)
        }
    }
}
