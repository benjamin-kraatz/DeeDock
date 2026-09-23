import AppKit

extension AppMeltController {
    /// The outgoing window stays open. Once the new member is committed, any partial AX
    /// failure retains that exact replacement in the existing Restore/Unpair recovery flow.
    func replaceWindow(_ pair: AppMeltPair, side: Int, with candidate: ApplicationWindowSummary) {
        guard pair.canChangeLayout, (0...1).contains(side),
              pairs.contains(where: { $0.id == pair.id }) else { return }
        if let comparison = pair.comparison?.state,
           comparison.isBusy || comparison.hasCapture || (comparison.draft != nil && comparison.savedURL == nil) {
            pair.replacement?.message = .meltReplacementComparePending
            return
        }
        let index = pair.sidesSwapped ? 1 - side : side
        guard !pairs.contains(where: { $0.id != pair.id && $0.windows.contains {
            $0.processIdentifier == candidate.processIdentifier
        } }) else { pair.replacement?.message = .meltReplacementInUse; return }
        pair.refreshPending = false
        pair.refreshTask?.cancel()
        run(pair) { [self] in
            let adopted: ApplicationWindowSummary
            let app: NSRunningApplication
            do {
                guard !(try await service.meltIsPaired(candidate.token, existing: pairs.flatMap(\.tokens))),
                      let running = NSRunningApplication(processIdentifier: candidate.processIdentifier), !running.isTerminated
                else { throw WindowActionError.unsupported }
                try Task.checkCancellation()
                app = running
                adopted = try await service.meltAdopt(candidate.token, sessionID: pair.sessionID)
            } catch is CancellationError {
                throw CancellationError()
            } catch {
                if !Task.isCancelled { pair.replacement?.message = .meltReplacementUnavailable }
                return
            }
            if Task.isCancelled {
                await service.meltRelease(adopted.token)
                throw CancellationError()
            }
            guard pairs.contains(where: { $0.id == pair.id }),
                  !pairs.contains(where: { $0.id != pair.id && $0.windows.contains {
                      $0.processIdentifier == candidate.processIdentifier
                  } }) else {
                await service.meltRelease(adopted.token)
                pair.replacement?.message = .meltReplacementInUse
                return
            }
            try Task.checkCancellation()
            try ensureActive(pair)
            let previous = pair.windows[index].token
            pair.chrome?.stop()
            pair.finderTools = nil
            pair.comparison?.stop(); pair.comparison = nil
            pair.windows[index] = adopted
            pair.names[index] = app.localizedName ?? app.bundleURL?.deletingPathExtension().lastPathComponent ?? ""
            pair.icons[index] = app.icon ?? NSImage()
            pair.applicationIDs[index] = app.bundleIdentifier ?? app.bundleURL?.standardizedFileURL.path
                ?? "process:\(app.processIdentifier)"
            pair.undoLayout = nil; pair.fittedFrom = nil; pair.acceptedFrames = []
            pair.chrome = AppMeltChrome(pair: pair, controller: self)
            await service.meltEndMove(pair.sessionID)
            await service.meltRelease(previous)
            try Task.checkCancellation()
            try ensureActive(pair)
            let settle = pair.observation.settleWait
            guard try await pair.observation.start(tokens: pair.layoutTokens, service: service, forceRestart: true) else {
                throw WindowActionError.unsupported
            }
            try ensureActive(pair)
            try await service.meltSetMinimized(false, token: adopted.token, settle: settle)
            try ensureActive(pair)
            let accepted = try await service.meltLayout(pair.layoutTokens,
                frames: AppMeltGeometry.windows(in: pair.frame, ratio: pair.ratio), displays: AppMeltGeometry.displays,
                settle: settle)
            try ensureActive(pair)
            pair.accept(accepted)
            try await service.meltRaise(pair.layoutTokens)
            try ensureActive(pair)
            try await service.meltActivateReplacement(adopted.token)
            try ensureActive(pair)
            pair.chrome?.update(show: true)
        }
    }
}
