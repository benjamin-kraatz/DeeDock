import Foundation

/// `LookoutBench dates`: prints the date range `DateHint` reads from each line of stdin, relative to `--now`
/// (yyyy-MM-dd, default today). For checking the parser against real queries.
enum DatesCommand {
    static func run(now: String?) throws {
        let reference = try now.map { text in
            guard let date = ISO8601DateFormatter.day.date(from: text) else { throw BenchFailure("--now \(text): not yyyy-MM-dd") }
            return date
        } ?? Date()
        let day = DateFormatter()
        day.dateFormat = "yyyy-MM-dd"
        while let line = readLine() {
            let range = DateHint.parse(line, now: reference).map {
                "\(day.string(from: $0.interval.start)) … \(day.string(from: $0.interval.end.addingTimeInterval(-1)))"
            }
            print("\(range ?? "–".padding(toLength: 23, withPad: " ", startingAt: 0))  \(line)")
        }
    }
}
