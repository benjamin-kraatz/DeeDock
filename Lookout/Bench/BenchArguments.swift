import Foundation

/// The bench's command line: a subcommand followed by `--name value` options.
struct BenchArguments {
    let command: String?
    private let options: [String: String]

    /// Parses `CommandLine.arguments`-style input (the first element is the executable).
    init(_ arguments: [String]) {
        command = arguments.dropFirst().first
        var options: [String: String] = [:]
        var rest = arguments.dropFirst(2).makeIterator()
        while let name = rest.next() {
            guard name.hasPrefix("--") else { continue }
            options[String(name.dropFirst(2))] = rest.next() ?? ""
        }
        self.options = options
    }

    /// The folder given as `--name`, or nil when it's missing.
    func folder(_ name: String) -> URL? {
        options[name].map { URL(fileURLWithPath: ($0 as NSString).expandingTildeInPath, isDirectory: true) }
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
