import Foundation
import Testing
@testable import DeeDock

/// The alias week is a calendar rule. These tests pin the edges so a later date change
/// cannot quietly stretch or shrink it.
struct ProductAliasTests {
    private let berlin = ProductAlias.localGregorian(timeZone: TimeZone(identifier: "Europe/Berlin")!)
    private let losAngeles = ProductAlias.localGregorian(timeZone: TimeZone(identifier: "America/Los_Angeles")!)

    @Test(arguments: [
        (2, 14),
        (7, 21),
        (8, 22),
        (11, 14),
    ])
    func weekRunsFromThreeDaysBeforeThroughThreeDaysAfter(month: Int, day: Int) {
        let occasion = try! #require(date(2026, month, day, hour: 15, calendar: berlin))
        #expect(ProductAlias.isActive(on: occasion, calendar: berlin))
        #expect(ProductAlias.applying(to: "Quit DOKK", on: occasion, calendar: berlin) == "Quit BIG DIKK")
        let first = try! #require(berlin.date(byAdding: .day, value: -ProductAlias.radius, to: occasion))
        let last = try! #require(berlin.date(byAdding: .day, value: ProductAlias.radius, to: occasion))
        #expect(ProductAlias.isActive(on: first, calendar: berlin))
        #expect(ProductAlias.isActive(on: last, calendar: berlin))
        let before = try! #require(berlin.date(byAdding: .day, value: -(ProductAlias.radius + 1), to: occasion))
        let after = try! #require(berlin.date(byAdding: .day, value: ProductAlias.radius + 1, to: occasion))
        #expect(!ProductAlias.isActive(on: before, calendar: berlin))
        #expect(!ProductAlias.isActive(on: after, calendar: berlin))
        #expect(ProductAlias.applying(to: "Quit DOKK", on: after, calendar: berlin) == "Quit DOKK")
    }

    @Test("The window is local calendar days, including the first and last midnights")
    func localDays() throws {
        let firstMorning = try #require(date(2026, 2, 11, hour: 0, minute: 30, calendar: berlin))
        let previousEvening = try #require(date(2026, 2, 10, hour: 23, minute: 59, calendar: berlin))
        let lastEvening = try #require(date(2026, 2, 17, hour: 23, minute: 59, calendar: berlin))
        let nextMorning = try #require(date(2026, 2, 18, hour: 0, minute: 0, calendar: berlin))
        #expect(ProductAlias.isActive(on: firstMorning, calendar: berlin))
        #expect(!ProductAlias.isActive(on: previousEvening, calendar: berlin))
        #expect(ProductAlias.isActive(on: lastEvening, calendar: berlin))
        #expect(!ProductAlias.isActive(on: nextMorning, calendar: berlin))
    }

    @Test("An instant just after Berlin midnight is still the previous day in Los Angeles")
    func timeZoneMovesTheDate() throws {
        let instant = try #require(date(2026, 2, 11, hour: 0, minute: 30, calendar: berlin))
        #expect(ProductAlias.isActive(on: instant, calendar: berlin))
        #expect(!ProductAlias.isActive(on: instant, calendar: losAngeles))
    }

    @Test("Ordinary days keep the canonical name")
    func ordinaryDay() throws {
        let day = try #require(date(2026, 10, 5, hour: 12, calendar: berlin))
        #expect(!ProductAlias.isActive(on: day, calendar: berlin))
        #expect(ProductAlias.applying(to: "DOKK", on: day, calendar: berlin) == "DOKK")
    }

    @Test("Only the product token changes")
    func replacesTheProductToken() throws {
        let day = try #require(date(2026, 8, 22, hour: 9, calendar: berlin))
        #expect(ProductAlias.applying(to: "DOKK beenden", on: day, calendar: berlin) == "BIG DIKK beenden")
        #expect(ProductAlias.applying(to: "BIG DIKK", on: day, calendar: berlin) == "BIG DIKK")
        #expect(ProductAlias.applying(to: "Your DOKK settings", on: day, calendar: berlin) == "Your BIG DIKK settings")
        #expect(ProductAlias.applying(to: "DOKK Dev", on: day, calendar: berlin) == "BIG DIKK Dev")
        #expect(ProductAlias.applying(to: "DOKK’s folder", on: day, calendar: berlin) == "BIG DIKK’s folder")
        #expect(ProductAlias.applying(to: "DOKK-Einstellungen", on: day, calendar: berlin) == "BIG DIKK-Einstellungen")
        #expect(ProductAlias.applying(to: "DeeDock stays DeeDock", on: day, calendar: berlin) == "DeeDock stays DeeDock")
        #expect(ProductAlias.applying(to: "dokk", on: day, calendar: berlin) == "dokk")
        #expect(ProductAlias.applying(to: "", on: day, calendar: berlin) == "")
    }

    @Test("Bundle display names change and identifiers do not")
    func bundleNames() {
        let info: [String: Any] = [
            "CFBundleName": "DOKK",
            "CFBundleDisplayName": "DOKK Dev",
            "CFBundleIdentifier": "de.benjaminkraatz.DeeDock",
            "DOKKAnalyticsAPIKey": "token",
        ]
        let renamed = ProductAlias.renamingDisplayedNames(in: info, active: true)
        #expect(renamed?["CFBundleName"] as? String == "BIG DIKK")
        #expect(renamed?["CFBundleDisplayName"] as? String == "BIG DIKK Dev")
        #expect(renamed?["CFBundleIdentifier"] as? String == "de.benjaminkraatz.DeeDock")
        #expect(renamed?["DOKKAnalyticsAPIKey"] as? String == "token")
        let unchanged = ProductAlias.renamingDisplayedNames(in: info, active: false)
        #expect(unchanged?["CFBundleName"] as? String == "DOKK")
        #expect(unchanged?["CFBundleDisplayName"] as? String == "DOKK Dev")
        #expect(ProductAlias.renamingDisplayedNames(in: nil, active: true) == nil)
    }

    private func date(_ year: Int, _ month: Int, _ day: Int, hour: Int, minute: Int = 0,
                      calendar: Calendar) -> Date? {
        calendar.date(from: DateComponents(year: year, month: month, day: day, hour: hour, minute: minute))
    }
}
