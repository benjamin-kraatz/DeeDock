import Foundation
import Testing
@testable import DeeDock

/// The dates a query names, in German and English, read against Saturday 21 November 2026.
struct LookoutDateHintTests {
    private let now = Calendar.lookout.date(from: DateComponents(year: 2026, month: 11, day: 21, hour: 12))!

    private func range(_ query: String) -> String? {
        guard let hint = DateHint.parse(query, now: now) else { return nil }
        let day = DateFormatter()
        day.calendar = .lookout
        day.dateFormat = "yyyy-MM-dd"
        return day.string(from: hint.interval.start) + "…" + day.string(from: hint.interval.end.addingTimeInterval(-1))
    }

    @Test func daysMonthsYearsAndSeasons() {
        #expect(range("Rechnung vom 15. Oktober 2026") == "2026-10-15…2026-10-15")
        #expect(range("October 15, 2026 invoice") == "2026-10-15…2026-10-15")
        #expect(range("Scan 15.10.2026") == "2026-10-15…2026-10-15")
        #expect(range("Stromrechnung März 2024") == "2024-03-01…2024-03-31")
        #expect(range("Steuer aus 2024") == "2024-01-01…2024-12-31")
        #expect(range("Rechnung Anfang 2024") == "2024-01-01…2024-04-30")
        #expect(range("Winter 2024 Heizung") == "2023-12-01…2024-02-29")
        // A month without a year is its latest that has begun.
        #expect(range("Fotos vom Dezember") == "2025-12-01…2025-12-31")
    }

    @Test func relativeToToday() {
        #expect(range("letzten Sommer Urlaub") == "2026-06-01…2026-08-31")
        #expect(range("last month invoice") == "2026-10-01…2026-10-31")
        #expect(range("Steuerbescheid von diesem Jahr") == "2026-01-01…2026-12-31")
        #expect(range("Chat von gestern") == "2026-11-20…2026-11-20")
        #expect(range("vor drei Wochen Chat") == "2026-10-22…2026-11-05")   // that week, half a week either side
    }

    @Test func codesAndPlainNumbersAreNoDates() {
        #expect(range("MW-2024-0047") == nil)
        #expect(range("Kundennummer 73421") == nil)
        #expect(range("may the force") == nil)
    }
}
