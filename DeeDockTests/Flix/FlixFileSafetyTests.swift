import Foundation
import Testing
import UniformTypeIdentifiers
@testable import DeeDock

/// What keeps Flix Files from reaching places it must not: symbolic links into protected folders,
/// Undo moving a file that took another's place, a partial move, and HTML conversions. Uses a
/// temporary folder that stands in for the home folder; nothing outside it is touched.
@Suite(.serialized)
struct FlixFileSafetyTests {
    /// A fresh home with Documents (protected) and Projects (not), resolved so `/var` and
    /// `/private/var` spell it the same way the walk does.
    private func makeHome() throws -> URL {
        let base = FileManager.default.temporaryDirectory.resolvingSymlinksInPath()
            .appending(path: "FlixFileSafety-\(UUID().uuidString)", directoryHint: .isDirectory)
        for folder in ["Documents/Work", "Projects"] {
            try FileManager.default.createDirectory(at: base.appending(path: folder), withIntermediateDirectories: true)
        }
        try Data("secret".utf8).write(to: base.appending(path: "Documents/tax.pdf"))
        try Data("work".utf8).write(to: base.appending(path: "Documents/Work/plan.pdf"))
        try Data("code".utf8).write(to: base.appending(path: "Projects/main.swift"))
        return base
    }

    private func link(_ path: String, to target: String, in home: URL) throws {
        try FileManager.default.createSymbolicLink(atPath: home.appending(path: path).path, withDestinationPath: target)
    }

    // MARK: Symbolic links

    @Test func linksIntoProtectedFoldersAreNotReadable() throws {
        let home = try makeHome()
        defer { try? FileManager.default.removeItem(at: home) }
        try link("Projects/docs", to: home.appending(path: "Documents").path, in: home)
        try link("Projects/tax.pdf", to: "../Documents/tax.pdf", in: home)
        try link("Projects/loop", to: "loop", in: home)
        let policy = FlixReadPolicy(home: home.path, allowedRoots: [])
        #expect(policy.canRead(home.appending(path: "Projects/main.swift").path))
        // The spelling is unprotected; what the links lead to is not.
        #expect(!policy.canRead(home.appending(path: "Projects/docs/tax.pdf").path))
        #expect(!policy.canRead(home.appending(path: "Projects/tax.pdf").path))
        #expect(!policy.canRead(home.appending(path: "Projects/loop").path))
        // A path that does not exist yet is judged by its spelling.
        #expect(policy.canRead(home.appending(path: "Projects/new.swift").path))
    }

    @Test func linksIntoAllowedFoldersStayReadable() throws {
        let home = try makeHome()
        defer { try? FileManager.default.removeItem(at: home) }
        try link("Projects/work", to: home.appending(path: "Documents/Work").path, in: home)
        let policy = FlixReadPolicy(home: home.path, allowedRoots: [home.appending(path: "Documents/Work").path])
        #expect(policy.canRead(home.appending(path: "Projects/work/plan.pdf").path))
        #expect(policy.canRead(home.appending(path: "Documents/Work/plan.pdf").path))
        #expect(!policy.canRead(home.appending(path: "Documents/tax.pdf").path))
        // Climbing out of the allowed folder through the link reaches Documents itself.
        #expect(!policy.canRead(home.appending(path: "Projects/work/../tax.pdf").path))
    }

    // MARK: Moves and Undo

    private func item(_ url: URL) -> FlixItem {
        FlixItem(path: url.path, name: url.lastPathComponent, kind: .document, activity: .opened, date: .now)
    }

    @MainActor @Test func aPartialMoveReportsEachFile() throws {
        let home = try makeHome()
        defer { try? FileManager.default.removeItem(at: home) }
        let target = home.appending(path: "Projects/Archive", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: target, withIntermediateDirectories: true)
        let present = item(home.appending(path: "Projects/main.swift"))
        let missing = item(home.appending(path: "Projects/gone.swift"))
        let report = FlixFileActions.move([missing, present], into: target)
        #expect(report.moved.map(\.item.id) == [present.id])
        #expect(report.failed.map(\.item.id) == [missing.id])
        #expect(report.moved.first?.identity != nil)
        #expect(FileManager.default.fileExists(atPath: target.appending(path: "main.swift").path))
    }

    @MainActor @Test func undoPutsBackOnlyTheFileThatWasMoved() throws {
        let home = try makeHome()
        defer { try? FileManager.default.removeItem(at: home) }
        let target = home.appending(path: "Projects/Archive", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: target, withIntermediateDirectories: true)
        let original = home.appending(path: "Projects/main.swift")
        let report = FlixFileActions.move([item(original)], into: target)
        let move = try #require(report.moved.first)

        // Something else took the moved file's place: Undo leaves it alone.
        try FileManager.default.removeItem(at: move.to)
        try Data("replacement".utf8).write(to: move.to)
        let refused = FlixFileActions.moveBack([move])
        #expect(refused.restored.isEmpty && refused.skipped.count == 1)
        #expect(!FileManager.default.fileExists(atPath: original.path))
        #expect(FileManager.default.fileExists(atPath: move.to.path))
    }

    @MainActor @Test func undoRestoresAnUntouchedMove() throws {
        let home = try makeHome()
        defer { try? FileManager.default.removeItem(at: home) }
        let target = home.appending(path: "Projects/Archive", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: target, withIntermediateDirectories: true)
        let original = home.appending(path: "Projects/main.swift")
        let move = try #require(FlixFileActions.move([item(original)], into: target).moved.first)
        let undone = FlixFileActions.moveBack([move])
        #expect(undone.restored.map(\.url.path) == [original.path])
        #expect(FileManager.default.fileExists(atPath: original.path))

        // A rename whose old name was taken meanwhile is not undone either.
        let rename = try #require(try FlixFileActions.rename(item(original), to: "app.swift"))
        try Data("new".utf8).write(to: original)
        #expect(FlixFileActions.undo(rename) == nil)
        #expect(FileManager.default.fileExists(atPath: rename.to.path))
    }

    @Test func identityTellsAReplacedFileApart() throws {
        let home = try makeHome()
        defer { try? FileManager.default.removeItem(at: home) }
        let url = home.appending(path: "Projects/main.swift")
        let identity = try #require(FlixFileIdentity.of(url))
        #expect(identity.matches(url))
        try FileManager.default.removeItem(at: url)
        try Data("code".utf8).write(to: url)
        #expect(!identity.matches(url))
    }

    // MARK: Conversions

    @Test func htmlAndWebArchivesAreNeverConverted() {
        let demand = FlixWindowDemand(acceptedTypes: [.pdf])
        for type in [UTType.html, .webArchive] {
            #expect(!FlixConversionPlanner.isText(type))
            #expect(FlixConversionPlanner.decision(type: type, byteSize: 1_000, isFile: true, demand: demand) == .unconvertible)
            #expect(FlixDocumentImport.documentType(for: type) == nil)
        }
        #expect(FlixConversionPlanner.decision(type: .rtf, byteSize: 1_000, isFile: true, demand: demand)
                == .convert(FlixConversionRecipe(format: .pdf)))
        #expect(FlixDocumentImport.documentType(for: .rtf) == .rtf)
        #expect(FlixDocumentImport.documentType(for: UTType("org.openxmlformats.wordprocessingml.document")!) == .officeOpenXML)
    }
}
