import Foundation
import Testing
@testable import DeeDock

/// An answer to one drop question never answers another, and a drag of a stale row cannot reach a
/// file that took its place.
@MainActor @Suite(.serialized)
struct FlixDropSafetyTests {
    private func identity(_ inode: UInt64, modified: Int64 = 1) -> FlixFileIdentity {
        FlixFileIdentity(device: 1, inode: inode, isDirectory: false, size: 10, modified: modified)
    }

    private func item(_ name: String, identity: FlixFileIdentity? = nil) -> FlixItem {
        FlixItem(path: "/w/" + name, name: name, kind: .document, activity: .saved, date: .now, fileIdentity: identity)
    }

    // MARK: Approvals

    @Test func anApprovalCoversOnlyItsQuestionItemAndFile() {
        let older = item("Offer v1.pdf", identity: identity(1))
        let newer = item("Offer v2.pdf", identity: identity(2))
        let sensitive = FlixDropConfirmation.sensitive(itemID: older.id, reason: nil, destination: nil)
        let version = FlixDropConfirmation.newerVersion(itemID: older.id, newerID: newer.id)
        var approvals = FlixDropApprovals()
        let now = Date.now
        approvals.approve(version, item: older, now: now)

        #expect(approvals.covers(version, item: older, now: now))
        // The version answer is not a sensitive answer, nor one for another item.
        #expect(!approvals.covers(sensitive, item: older, now: now))
        #expect(!approvals.coversSensitive(newer, now: now))
        #expect(!approvals.covers(.newerVersion(itemID: newer.id, newerID: older.id), item: newer, now: now))
        // A yet newer version asks again.
        #expect(!approvals.covers(.newerVersion(itemID: older.id, newerID: UUID()), item: older, now: now))
        // The same row after its file was replaced asks again.
        var replaced = older
        replaced.fileIdentity = identity(1, modified: 2)
        #expect(!approvals.covers(version, item: replaced, now: now))
        // And the answer expires.
        #expect(!approvals.covers(version, item: older, now: now.addingTimeInterval(FlixDropApprovals.lifetime + 1)))
    }

    @Test func useNewerReevaluatesTheSensitiveVerdictOfTheNewerFile() {
        let intelligence = FlixIntelligence()
        let older = item("Contract v1.pdf", identity: identity(1))
        let newer = item("Contract v2.pdf", identity: identity(2))
        intelligence.reviseAnnotation(for: older.id) { $0.versionGroup = "contract"; $0.versionRank = 1 }
        intelligence.reviseAnnotation(for: newer.id) {
            $0.versionGroup = "contract"; $0.versionRank = 2; $0.isSensitive = true
        }
        var approvals = FlixDropApprovals()

        #expect(intelligence.dropConfirmation(for: [older], context: nil, approvals: approvals)
                == .newerVersion(itemID: older.id, newerID: newer.id))
        // **Use Newer** swaps in the newer file and grants nothing, so its own question comes next.
        let next = intelligence.dropConfirmation(for: [newer], context: nil, approvals: approvals)
        guard let next, case .sensitive(let id, _, _) = next else {
            Issue.record("expected the sensitive question, got \(String(describing: next))")
            return
        }
        #expect(id == newer.id)
        approvals.approve(.sensitive(itemID: newer.id, reason: nil, destination: nil), item: newer)
        #expect(intelligence.dropConfirmation(for: [newer], context: nil, approvals: approvals) == nil)
    }

    @Test func aFlaggedOlderVersionAsksBothQuestionsInTurn() {
        let intelligence = FlixIntelligence()
        let older = item("Passport scan.pdf", identity: identity(1))
        let newer = item("Passport scan 2.pdf", identity: identity(2))
        intelligence.reviseAnnotation(for: older.id) { $0.versionGroup = "passport"; $0.versionRank = 1; $0.isSensitive = true }
        intelligence.reviseAnnotation(for: newer.id) { $0.versionGroup = "passport"; $0.versionRank = 2 }
        var approvals = FlixDropApprovals()

        let first = intelligence.dropConfirmation(for: [older], context: nil, approvals: approvals)
        guard let first, case .sensitive = first else {
            Issue.record("expected the sensitive question first")
            return
        }
        approvals.approve(first, item: older)
        let second = FlixDropConfirmation.newerVersion(itemID: older.id, newerID: newer.id)
        #expect(intelligence.dropConfirmation(for: [older], context: nil, approvals: approvals) == second)
        approvals.approve(second, item: older)
        #expect(intelligence.dropConfirmation(for: [older], context: nil, approvals: approvals) == nil)
    }

    // MARK: Dragged files

    private func makeFolder() throws -> URL {
        let folder = FileManager.default.temporaryDirectory.resolvingSymlinksInPath()
            .appending(path: "FlixDropSafety-\(UUID().uuidString)", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        return folder
    }

    @Test func aReplacedFileIsReportedAsChanged() throws {
        let folder = try makeFolder()
        defer { try? FileManager.default.removeItem(at: folder) }
        let listed = folder.appending(path: "Invoice.pdf")
        let other = folder.appending(path: "Notes.txt")
        let unlisted = folder.appending(path: "Unlisted.txt")
        try Data("original".utf8).write(to: listed)
        try Data("notes".utf8).write(to: other)
        try Data("x".utf8).write(to: unlisted)
        var identities: [String: FlixFileIdentity?] = [:]
        identities[FlixPaths.standardized(listed.path)] = .some(FlixFileIdentity.of(listed))
        // A row that had no identity yet cannot vouch for its file.
        identities[FlixPaths.standardized(other.path)] = .some(nil)
        #expect(identities.count == 2)
        let files = FlixDraggedFiles(identities: identities)
        #expect(files.changed(among: [listed, unlisted]).isEmpty)
        #expect(files.changed(among: [other]) == [other])

        // Another file takes the listed one's place.
        try FileManager.default.removeItem(at: listed)
        try Data("a different file".utf8).write(to: listed)
        #expect(files.changed(among: [listed, unlisted]) == [listed])
        try FileManager.default.removeItem(at: listed)
        #expect(files.changed(among: [listed]) == [listed])
    }

    @Test func theStaleMessageNamesTheFile() {
        #expect(FlixDraggedFileChanged(name: "Invoice.pdf").localizedDescription.contains("Invoice.pdf"))
    }
}
