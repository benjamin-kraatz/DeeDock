import Foundation

/// The bench's command line: a subcommand followed by `--name value` options. An option may be repeated
/// (`--root a --root b`); `folder` reads its last value, `folders` all of them.
struct BenchArguments {
    let command: String?
    private let options: [String: [String]]

    /// Parses `CommandLine.arguments`-style input (the first element is the executable).
    init(_ arguments: [String]) {
        command = arguments.dropFirst().first
        var options: [String: [String]] = [:]
        var rest = arguments.dropFirst(2).makeIterator()
        while let name = rest.next() {
            guard name.hasPrefix("--") else { continue }
            options[String(name.dropFirst(2)), default: []].append(rest.next() ?? "")
        }
        self.options = options
    }

    /// Every folder given as `--name`, in order.
    ///
    /// - Throws: `BenchFailure` when one isn't a folder.
    func folders(_ name: String) throws -> [URL] {
        try (options[name] ?? []).map { path in
            let folder = Self.url(path)
            var isFolder: ObjCBool = false
            guard FileManager.default.fileExists(atPath: folder.path, isDirectory: &isFolder), isFolder.boolValue else {
                throw BenchFailure("--\(name): no folder at \(folder.path)")
            }
            return folder
        }
    }

    private static func url(_ path: String) -> URL {
        URL(fileURLWithPath: (path as NSString).expandingTildeInPath, isDirectory: true)
    }

    /// The folder given as `--name`, or nil when it's missing.
    func folder(_ name: String) -> URL? {
        options[name]?.last.map { Self.url($0) }
    }

    /// The file given as `--name`, or nil when it's missing.
    func file(_ name: String) -> URL? {
        options[name]?.last.map { URL(fileURLWithPath: ($0 as NSString).expandingTildeInPath) }
    }

    /// The number given as `--name`, or nil when it's missing.
    ///
    /// - Throws: `BenchFailure` when it isn't a number.
    func number(_ name: String) throws -> Double? {
        guard let text = options[name]?.last else { return nil }
        guard let value = Double(text) else { throw BenchFailure("--\(name): \(text) isn't a number") }
        return value
    }

    /// The folder given as `--name`.
    ///
    /// - Throws: `BenchFailure` when the option is missing or isn't a folder.
    func requiredFolder(_ name: String) throws -> URL {
        guard let folder = folder(name) else { throw BenchFailure("missing --\(name) <folder>") }
        var isFolder: ObjCBool = false
        guard FileManager.default.fileExists(atPath: folder.path, isDirectory: &isFolder), isFolder.boolValue else {
            throw BenchFailure("--\(name): no folder at \(folder.path)")
        }
        return folder
    }
}

/// A reason the bench stops, printed as is.
struct BenchFailure: Error, CustomStringConvertible {
    let description: String
    init(_ description: String) { self.description = description }
}
