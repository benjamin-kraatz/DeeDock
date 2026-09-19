import AppKit

nonisolated struct MeltFinderLocation: Equatable, Sendable {
    let windowID: Int32
    let url: URL
}

nonisolated enum MeltFinderError: Error {
    case unavailable, changed, overlapping, unsupported, automation(String)
}

/// Finder scripting is serialized off the UI thread. Match the retained AX window's bounds
/// uniquely, then use Finder's window ID; never navigate Finder's front window by position.
actor MeltFinderAutomation {
    func locations(frames: [CGRect]) throws -> [MeltFinderLocation] {
        let result = try execute("""
        tell application id "com.apple.finder"
            set output to {}
            repeat with w in (get Finder windows)
                try
                    set t to get target of w
                    if class of t is folder or class of t is disk then
                        set b to get bounds of w
                        set p to get URL of t
                        set end of output to {id of w, p, item 1 of b, item 2 of b, item 3 of b, item 4 of b}
                    end if
                end try
            end repeat
            return output
        end tell
        """)
        var available: [(MeltFinderLocation, CGRect)] = []
        if result.numberOfItems > 0 {
            for index in 1...result.numberOfItems {
                guard let row = result.atIndex(index), row.numberOfItems == 6,
                      let path = row.atIndex(2)?.stringValue,
                      let url = URL(string: path), url.isFileURL else { continue }
                let numbers = (3...6).map { CGFloat(row.atIndex($0)?.int32Value ?? 0) }
                available.append((MeltFinderLocation(windowID: row.atIndex(1)?.int32Value ?? 0,
                    url: url),
                    CGRect(x: numbers[0], y: numbers[1], width: numbers[2] - numbers[0], height: numbers[3] - numbers[1])))
            }
        }
        let locations = try frames.map { frame in
            let matches = available.filter { AppMeltGeometry.nearlyEqual($0.1, frame) }
            guard matches.count == 1 else { throw MeltFinderError.unavailable }
            return matches[0].0
        }
        guard locations.count == 2, locations[0].windowID != locations[1].windowID else { throw MeltFinderError.unavailable }
        return locations
    }

    func navigate(from source: MeltFinderLocation, to destination: MeltFinderLocation) throws {
        // Check both targets inside the same script before changing one. Quoting covers Finder
        // paths containing quotes, backslashes or line breaks; no source text comes from titles.
        _ = try execute("""
        tell application id "com.apple.finder"
            set sourceWindow to Finder window id \(source.windowID)
            set destinationWindow to Finder window id \(destination.windowID)
            set sourceTarget to get target of sourceWindow
            set destinationTarget to get target of destinationWindow
            if (get URL of sourceTarget) is not \(literal(source.url.absoluteString)) then error number 7001
            if (get URL of destinationTarget) is not \(literal(destination.url.absoluteString)) then error number 7001
            set target of destinationWindow to sourceTarget
        end tell
        """)
    }

    private func literal(_ value: String) -> String {
        "\"" + value.replacingOccurrences(of: "\\", with: "\\\\").replacingOccurrences(of: "\"", with: "\\\"")
            .replacingOccurrences(of: "\r", with: "\\r").replacingOccurrences(of: "\n", with: "\\n") + "\""
    }

    private func execute(_ source: String) throws -> NSAppleEventDescriptor {
        try Task.checkCancellation()
        var error: NSDictionary?
        guard let script = NSAppleScript(source: source) else { throw MeltFinderError.unavailable }
        let result = script.executeAndReturnError(&error)
        if let error, (error[NSAppleScript.errorNumber] as? NSNumber)?.intValue == 7001 { throw MeltFinderError.changed }
        if let error { throw MeltFinderError.automation(error[NSAppleScript.errorMessage] as? String ?? "") }
        return result
    }
}
