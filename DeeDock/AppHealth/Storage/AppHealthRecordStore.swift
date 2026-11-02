import Foundation
import os

/// What Settings shows about the stored data.
nonisolated struct AppHealthStorageSummary: Sendable, Equatable {
    var bytes: Int64
    /// The start of the oldest file's day, or nil without data.
    var oldest: Date?
    /// How many days have a file.
    var days: Int

    static let empty = AppHealthStorageSummary(bytes: 0, oldest: nil, days: 0)

    var hasData: Bool { days > 0 && bytes > 0 }
}

/// Persists App Health records. The live implementation is `AppHealthRecordStore`; tests pass a fake.
nonisolated protocol AppHealthRecording: Actor {
    /// Appends records in order to today's file. Drops them while today's file is over the cap.
    func append(_ records: [AppHealthRecord])
    func summary() -> AppHealthStorageSummary
    /// Closes the open file and removes the whole directory.
    func deleteAll() throws
    /// Writes a zip of every file plus `manifest` to `destination`.
    func export(to destination: URL, manifest: AppHealthExportManifest) throws
    /// Closes the open file. The next append reopens it.
    func close()
}

/// Appends App Health records as JSON Lines to one file per local day, and enforces retention.
///
/// Files live in `~/Library/Application Support/DOKK/AppHealth/` (0700, excluded from backups), each 0600. The
/// store keeps today's file open and appends one batch per call with a single write, so a tick's records land
/// together. It tracks every file's size in memory after one directory scan, so summaries and the cap check
/// never touch the disk. JSON encoding happens here, off the main actor.
actor AppHealthRecordStore: AppHealthRecording {
    private static let logger = Logger(subsystem: Bundle.main.bundleIdentifier ?? "DOKK", category: "AppHealth")

    private let directory: URL
    private let retention: AppHealthRetention
    private let calendar: Calendar
    private let now: @Sendable () -> Date
    private let encoder = AppHealthRecord.makeEncoder()
    private var handle: FileHandle?
    private var handleDay: AppHealthDay?
    /// Bytes per day, from one scan of the directory. Nil until the first use.
    private var files: [AppHealthDay: Int64]?
    /// Set when today's file alone reached the cap; appends wait for the next day.
    private var fullDay: AppHealthDay?

    static var defaultDirectory: URL {
        URL.applicationSupportDirectory.appending(path: "DOKK/AppHealth", directoryHint: .isDirectory)
    }

    init(directory: URL = AppHealthRecordStore.defaultDirectory, retention: AppHealthRetention = .standard,
         calendar: Calendar = .current, now: @escaping @Sendable () -> Date = { Date() }) {
        self.directory = directory
        self.retention = retention
        self.calendar = calendar
        self.now = now
    }

    func append(_ records: [AppHealthRecord]) {
        guard !records.isEmpty else { return }
        let today = AppHealthDay(now(), calendar: calendar)
        guard fullDay != today else { return }
        // The first append after launch, and the first of each new day, opens a new file: prune then.
        if handleDay != today {
            closeHandle()
            prune(today: today)
        }
        var data = Data()
        for record in records {
            do {
                data.append(try encoder.encode(record))
                data.append(0x0A)
            } catch {
                Self.logger.error("App Health could not encode a \(record.type, privacy: .public) record")
            }
        }
        guard !data.isEmpty else { return }
        do {
            let handle = try openHandle(for: today)
            try handle.seekToEnd()
            try handle.write(contentsOf: data)
        } catch {
            Self.logger.error("App Health could not write today's file: \(error.localizedDescription, privacy: .public)")
            closeHandle()
            return
        }
        var sizes = scannedFiles()
        let todayBytes = (sizes[today] ?? 0) + Int64(data.count)
        sizes[today] = todayBytes
        files = sizes
        if sizes.values.reduce(0, +) > retention.maximumBytes { prune(today: today) }
        if retention.isOverCap(todayBytes: todayBytes) {
            fullDay = today
            closeHandle()
            Self.logger.notice("App Health paused writing until tomorrow: today's file reached the size cap")
        }
    }

    func summary() -> AppHealthStorageSummary {
        let sizes = scannedFiles()
        guard let oldest = sizes.keys.min() else { return .empty }
        return AppHealthStorageSummary(bytes: sizes.values.reduce(0, +), oldest: oldest.start(in: calendar),
                                       days: sizes.count)
    }

    func deleteAll() throws {
        closeHandle()
        files = [:]
        fullDay = nil
        guard FileManager.default.fileExists(atPath: directory.path) else { return }
        try FileManager.default.removeItem(at: directory)
    }

    func export(to destination: URL, manifest: AppHealthExportManifest) throws {
        try? handle?.synchronize()
        let days = scannedFiles().keys.sorted()
        var manifest = manifest
        manifest.files = days.map(\.fileName)
        try AppHealthExportArchive.write(files: days.map { directory.appending(path: $0.fileName) },
                                         manifest: manifest, to: destination)
    }

    func close() {
        closeHandle()
    }

    // MARK: - Files

    private func scannedFiles() -> [AppHealthDay: Int64] {
        if let files { return files }
        var sizes: [AppHealthDay: Int64] = [:]
        let entries = (try? FileManager.default.contentsOfDirectory(
            at: directory, includingPropertiesForKeys: [.fileSizeKey], options: [.skipsHiddenFiles])) ?? []
        for url in entries {
            guard let day = AppHealthDay(fileName: url.lastPathComponent) else { continue }
            sizes[day] = Int64((try? url.resourceValues(forKeys: [.fileSizeKey]))?.fileSize ?? 0)
        }
        files = sizes
        return sizes
    }

    private func prune(today: AppHealthDay) {
        var sizes = scannedFiles()
        let doomed = retention.filesToDelete(sizes.map { AppHealthRetention.File(day: $0.key, bytes: $0.value) },
                                             today: today, calendar: calendar)
        for day in doomed {
            do {
                try FileManager.default.removeItem(at: directory.appending(path: day.fileName))
                sizes[day] = nil
            } catch {
                Self.logger.error("App Health could not remove an expired file: \(error.localizedDescription, privacy: .public)")
            }
        }
        files = sizes
        if fullDay != nil, fullDay != today { fullDay = nil }
    }

    private func openHandle(for day: AppHealthDay) throws -> FileHandle {
        if let handle, handleDay == day { return handle }
        closeHandle()
        try prepareDirectory()
        let url = directory.appending(path: day.fileName)
        if !FileManager.default.fileExists(atPath: url.path) {
            FileManager.default.createFile(atPath: url.path, contents: nil, attributes: [.posixPermissions: 0o600])
        }
        let opened = try FileHandle(forWritingTo: url)
        handle = opened
        handleDay = day
        return opened
    }

    private func prepareDirectory() throws {
        guard !FileManager.default.fileExists(atPath: directory.path) else { return }
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true,
                                                attributes: [.posixPermissions: 0o700])
        var url = directory
        var values = URLResourceValues()
        values.isExcludedFromBackup = true
        try? url.setResourceValues(values)
    }

    private func closeHandle() {
        try? handle?.close()
        handle = nil
        handleDay = nil
    }
}
