import Foundation
import Testing
@testable import DeeDock

/// The JSON Lines schema: the shared envelope, omitted nil fields, rounding, and the ten-minute history.
struct AppHealthRecordTests {
    private let date = Date(timeIntervalSince1970: 1_793_000_000.123_456)

    private func object(_ record: AppHealthRecord) throws -> [String: Any] {
        let data = try AppHealthRecord.makeEncoder().encode(record)
        #expect(!data.contains(0x0A))
        return try #require(try JSONSerialization.jsonObject(with: data) as? [String: Any])
    }

    private func sample(at offset: TimeInterval, cpu: Double = 0.123_456_7) -> AppHealthSample {
        AppHealthSample(app: "com.example.App", kind: .accessory, timestamp: date.addingTimeInterval(offset),
                        interval: 20.004_9, cpuMain: cpu, cpuHelpers: 0, mem: 5_000, memMain: 4_000, procs: 2,
                        wakeups: 405, energy: nil, frontmost: true)
    }

    @Test("Every record carries v, type, and ts in milliseconds, flattened with its fields")
    func envelope() throws {
        let json = try object(AppHealthRecord(.event(.collector(.collectorStart, reason: .enabled)), at: date))
        #expect(json["v"] as? Int == 1)
        #expect(json["type"] as? String == "event")
        #expect(json["ts"] as? Double == 1_793_000_000.123)
        #expect(json["event"] as? String == "collectorStart")
        #expect(json["reason"] as? String == "enabled")
        #expect(json["app"] == nil)
        #expect(json["crashReport"] == nil)
    }

    @Test("Sample rows round CPU to milliseconds and rates to tenths, and omit unchecked fields")
    func sampleRounding() throws {
        let json = try object(AppHealthRecord(.sample(AppHealthSampleRecord(sample(at: 0), why: .growth)), at: date))
        #expect(json["cpu"] as? Double == 0.123)
        #expect(json["interval"] as? Double == 20.005)
        #expect(json["cpuPct"] as? Double == 0.6)
        #expect(json["wakeupsPerSec"] as? Double == 20.2)
        #expect(json["kind"] as? String == "accessory")
        #expect(json["load"] as? String == "main")
        #expect(json["why"] as? String == "growth")
        #expect(json["frontmost"] as? Bool == true)
        #expect(json["energy"] == nil)
        #expect(json["hang"] == nil)
        #expect(json["hangMs"] == nil)
    }

    @Test("Records decode back to what was written")
    func roundTrip() throws {
        let id = UUID()
        let records = [
            AppHealthRecord(.tick(AppHealthTickRecord(interval: 20, frontmost: nil, idle: 3, power: .battery,
                                                      thermal: .fair, apps: 12, written: 2, costMs: 4.2, ax: false)),
                            at: date),
            AppHealthRecord(.prompt(AppHealthPromptRecord(id: id, app: "com.example.App", kind: .regular,
                                                          trigger: .rule, reasons: [.cpu, .background], anchor: .tile)),
                            at: date),
            AppHealthRecord(.label(AppHealthLabelRecord(id: id, app: "com.example.App", answer: .misbehaving,
                                                        detail: .spinning, from: date.addingTimeInterval(-300), to: date,
                                                        source: .prompt, responseSeconds: 4.5)), at: date),
        ]
        let encoder = AppHealthRecord.makeEncoder()
        for record in records {
            let decoded = try JSONDecoder().decode(AppHealthRecord.self, from: encoder.encode(record))
            #expect(decoded.body == record.body)
            #expect(decoded.type == record.type)
        }
    }

    @Test("History keeps 30 ticks per app and backfills each unwritten tick once")
    func history() {
        var history = AppHealthHistory()
        for tick in 0..<35 { history.append(sample(at: Double(tick) * 20), written: tick % 2 == 0) }
        let entries = history.entries(for: "com.example.App")
        #expect(entries.count == AppHealthHistory.capacity)
        #expect(entries.first?.sample.timestamp == date.addingTimeInterval(5 * 20))

        let window = (from: date.addingTimeInterval(20 * 20), to: date.addingTimeInterval(25 * 20))
        let taken = history.takeUnwritten(app: "com.example.App", from: window.from, to: window.to)
        #expect(taken.map(\.timestamp) == [21, 23, 25].map { date.addingTimeInterval(Double($0) * 20) })
        #expect(history.takeUnwritten(app: "com.example.App", from: window.from, to: window.to).isEmpty)

        history.removeEntries(for: "com.example.App", through: date.addingTimeInterval(30 * 20))
        #expect(history.entries(for: "com.example.App").count == 4)
        history.removeEntries(for: "com.example.App", through: .distantFuture)
        #expect(history.apps.isEmpty)
    }
}
