import Foundation
import Testing
@testable import DeeDock

/// How the reader turns Launch Services replies into background apps, and when it turns the
/// feature off. Replies come from a fake record source; no test calls Launch Services.
struct LaunchServicesBackgroundReaderTests {
    private static let url = URL(fileURLWithPath: "/Applications/Fixture.app", isDirectory: true).standardizedFileURL

    @Test("A well-formed background record with a live process becomes a background app")
    func wellFormed() async throws {
        let child = try await BackgroundProcessFixture.start(.plain)
        defer { child.end() }
        let applications = try LaunchServicesBackgroundReader.read(
            from: FakeRecordSource([.application(pids: [child.pid])])).get()

        let application = try #require(applications.first)
        #expect(applications.count == 1)
        #expect(application.bundleURL == Self.url)
        #expect(application.bundleIdentifier == "fixture")
        #expect(application.name == "Fixture")
        #expect(application.processes == [child.identity])
    }

    @Test("Child applications count, and two records of one bundle merge into one app")
    func childrenAndMerge() async throws {
        let first = try await BackgroundProcessFixture.start(.plain)
        defer { first.end() }
        let second = try await BackgroundProcessFixture.start(.plain)
        defer { second.end() }
        let source = FakeRecordSource([
            .application(pids: [first.pid]),
            .application(children: [.child(pid: second.pid)]),
        ])

        let applications = try LaunchServicesBackgroundReader.read(from: source).get()
        #expect(applications.count == 1)
        #expect(Set(applications.first?.processes ?? []) == [first.identity, second.identity])
    }

    @Test("Vanished records, records not in background, other app types, and dead processes are skipped")
    func skipped() async throws {
        let child = try await BackgroundProcessFixture.start(.plain)
        defer { child.end() }
        let source = FakeRecordSource([
            FakeRecord(state: .vanished, details: .vanished),
            .application(flag: false, pids: [child.pid]),
            .application(type: "UIElement", pids: [child.pid]),
            FakeRecord(state: .values(["background": true, "type": "Foreground"]), details: .vanished),
            .application(pids: [0, 1, getpid()]),
            .application(children: [FakeRecord(state: .vanished, details: .vanished, pid: .vanished)]),
        ])
        #expect(try LaunchServicesBackgroundReader.read(from: source).get().isEmpty)
    }

    @Test("A malformed reply turns the reader off, even beside well-formed records", arguments: Malformation.allCases)
    func malformed(_ malformation: Malformation) async throws {
        let child = try await BackgroundProcessFixture.start(.plain)
        defer { child.end() }
        let source = FakeRecordSource([.application(pids: [child.pid]), malformation.record])
        #expect(throws: LaunchServicesBackgroundReader.Unavailability.unexpectedResult) {
            try LaunchServicesBackgroundReader.read(from: source).get()
        }
    }

    @Test("A record list that is not an array turns the reader off")
    func noList() {
        #expect(throws: LaunchServicesBackgroundReader.Unavailability.unexpectedResult) {
            try LaunchServicesBackgroundReader.read(from: FakeRecordSource(nil)).get()
        }
    }

    /// One way a single record's reply can differ from the verified shape.
    nonisolated enum Malformation: CaseIterable, CustomTestStringConvertible, Sendable {
        case stateNotDictionary, flagNotNumber, typeNotString, detailsNotDictionary, pathNotString
        case nameNotString, identifierNotString, pidsNotNumbers, childrenNotArray
        case childReplyNotDictionary, childPIDNotNumber
        case flagIsNumber, pidOutOfRange, pidFraction, pidIsBoolean, childPIDOutOfRange
        // A malformed value next to one that would skip the record must still be caught.
        case typeMalformedBesideFalseFlag, nameMalformedBesideEmptyPath, pidsMalformedBesideEmptyPath
        // Launch Services leaves absent values out; an explicit null is malformed, not absent.
        case flagNull, typeNull, pathNull, nameNull, pidsNull, childPIDNull

        var testDescription: String { "\(self)" }

        var record: FakeRecord {
            switch self {
            case .stateNotDictionary: FakeRecord(state: .malformed, details: .vanished)
            case .flagNotNumber: .application(flag: "yes")
            case .typeNotString: .application(type: NSNumber(value: 1))
            case .detailsNotDictionary:
                FakeRecord(state: .values(["background": true, "type": "Foreground"]), details: .malformed)
            case .pathNotString: .application(overrides: ["path": NSNumber(value: 1)])
            case .nameNotString: .application(overrides: ["name": NSNumber(value: 1)])
            case .identifierNotString: .application(overrides: ["id": ["fixture"]])
            case .pidsNotNumbers: .application(overrides: ["pids": "12"])
            case .childrenNotArray: .application(overrides: ["children": "none"])
            case .childReplyNotDictionary:
                .application(children: [FakeRecord(state: .vanished, details: .vanished, pid: .malformed)])
            case .childPIDNotNumber:
                .application(children: [FakeRecord(state: .vanished, details: .vanished, pid: .values(["pid": "12"]))])
            case .flagIsNumber: .application(flag: NSNumber(value: 1))
            case .pidOutOfRange: .application(overrides: ["pids": [NSNumber(value: (Int64(1) << 32) + Int64(getpid()))]])
            case .pidFraction: .application(overrides: ["pids": [NSNumber(value: 12.5)]])
            case .pidIsBoolean: .application(overrides: ["pids": [NSNumber(value: true)]])
            case .childPIDOutOfRange:
                .application(children: [FakeRecord(state: .vanished, details: .vanished,
                                                   pid: .values(["pid": NSNumber(value: Int64(1) << 32)]))])
            case .typeMalformedBesideFalseFlag: .application(flag: false, type: NSNumber(value: 1))
            case .nameMalformedBesideEmptyPath: .application(overrides: ["path": "", "name": NSNumber(value: 1)])
            case .pidsMalformedBesideEmptyPath: .application(overrides: ["path": "", "pids": "12"])
            case .flagNull: .application(flag: NSNull())
            case .typeNull: .application(type: NSNull())
            case .pathNull: .application(overrides: ["path": NSNull()])
            case .nameNull: .application(overrides: ["name": NSNull()])
            case .pidsNull: .application(overrides: ["pids": NSNull()])
            case .childPIDNull:
                .application(children: [FakeRecord(state: .vanished, details: .vanished, pid: .values(["pid": NSNull()]))])
            }
        }
    }
}

/// One application record and its replies. A class, because the reader passes records around
/// as objects, as it does Launch Services' own record references.
nonisolated final class FakeRecord {
    let state: BackgroundRecordReply
    let details: BackgroundRecordReply
    let pid: BackgroundRecordReply

    init(state: BackgroundRecordReply, details: BackgroundRecordReply, pid: BackgroundRecordReply = .vanished) {
        self.state = state
        self.details = details
        self.pid = pid
    }

    /// A Foreground record of `/Applications/Fixture.app` running in background.
    static func application(flag: Any = true, type: Any = "Foreground", pids: [pid_t] = [],
                            children: [FakeRecord] = [], overrides: [String: Any] = [:]) -> FakeRecord {
        var details: [String: Any] = ["path": "/Applications/Fixture.app", "name": "Fixture", "id": "fixture",
                                      "pids": pids.map { NSNumber(value: $0) }, "children": children]
        details.merge(overrides) { _, override in override }
        return FakeRecord(state: .values(["background": flag, "type": type]), details: .values(details))
    }

    /// A non-foreground child application with one process.
    static func child(pid: pid_t) -> FakeRecord {
        FakeRecord(state: .vanished, details: .vanished, pid: .values(["pid": NSNumber(value: pid)]))
    }
}

/// Answers the reader from fake records, keyed like the real source but with readable names.
nonisolated struct FakeRecordSource: BackgroundRecordSource {
    let keys = BackgroundRecordKeys(background: "background", type: "type", foregroundType: "Foreground",
                                    bundlePath: "path", displayName: "name", bundleIdentifier: "id", pid: "pid",
                                    coalitionPIDs: "pids", childApplications: "children")
    let list: [FakeRecord]?

    init(_ list: [FakeRecord]?) { self.list = list }

    func records() -> [AnyObject]? { list }

    func information(_ record: AnyObject, _ requested: [String]) -> BackgroundRecordReply {
        guard let record = record as? FakeRecord else { return .malformed }
        if requested.contains(keys.background) { return record.state }
        if requested == [keys.pid] { return record.pid }
        return record.details
    }
}
