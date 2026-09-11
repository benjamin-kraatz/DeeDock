import Foundation

/// A static SVG for the README and landing page. It adapts to light and dark through `prefers-color-scheme`,
/// which GitHub honors for images. Every value is also printed as text, and RESULTS.md carries the table view.
enum Chart {
    private static let width = 720.0
    private static let labelWidth = 250.0
    private static let valueWidth = 110.0
    private static var plotWidth: Double { width - labelWidth - valueWidth - 48 }

    static func svg(_ summary: RunSummary) -> String {
        var body: [String] = []
        var y = 32.0
        body.append(text("DDock performance", x: 24, y: y, className: "title"))
        y += 20
        body.append(text("\(summary.machine["model"] ?? "") · \(summary.machine["os"] ?? "") · commit \(summary.commit)",
                         x: 24, y: y, className: "muted"))
        y += 36

        if let ddock = summary.resources["ddock"] {
            let dock = summary.resources["dock"]
            let window = ddock.seconds >= 120 ? "\(Int((ddock.seconds / 60).rounded())) minutes" : "\(Int(ddock.seconds.rounded())) seconds"
            body.append(text("Idle, same \(window) on the same Mac (lower is better)", x: 24, y: y, className: "heading"))
            y += 16
            body.append(legend(x: 24, y: y, dock: dock != nil))
            y += 22
            let rows: [(String, Double, Double?, String)] = [
                ("Memory (MiB)", ddock.footprintMiB?.p50 ?? 0, dock?.footprintMiB?.p50, " MiB"),
                ("CPU (% of one core)", ddock.cpuPercent, dock?.cpuPercent, " %"),
                ("Wakeups per second", ddock.wakeupsPerSecond, dock?.wakeupsPerSecond, "/s"),
            ]
            for (label, mine, theirs, unit) in rows {
                // Each row keeps its own scale: memory, CPU, and wakeups share no unit.
                let scale = max(mine, theirs ?? 0, 1e-9)
                body.append(text(label, x: 24, y: y + 12, className: "label"))
                body.append(bar(x: labelWidth, y: y, length: mine / scale * plotWidth, className: "ddock"))
                body.append(text("DDock " + Format.number(mine) + unit, x: labelWidth + mine / scale * plotWidth + 8, y: y + 11, className: "value"))
                if let theirs {
                    body.append(bar(x: labelWidth, y: y + 16, length: theirs / scale * plotWidth, className: "dock"))
                    body.append(text("Dock " + Format.number(theirs) + unit, x: labelWidth + theirs / scale * plotWidth + 8, y: y + 27, className: "value"))
                }
                y += theirs == nil ? 26 : 44
            }
            y += 20
        }

        let headline = ["launcherOpenFromClick", "launcherOpen", "hoverResponse", "dockRevealOverDelay",
                        "stackOpen", "peekOpen", "launcherRank", "magnifyUpdate"]
        // Prefer end-to-end numbers; drop the in-process twin when the real-input metric exists.
        let keys = headline.filter { key in
            guard summary.metrics[key] != nil else { return false }
            if key == "launcherOpen" { return summary.metrics["launcherOpenFromClick"] == nil }
            if key == "magnifyUpdate" { return summary.metrics["hoverResponse"] == nil }
            return true
        }
        if !keys.isEmpty {
            body.append(text("Response time in ms: bar is p50, whisker reaches p95", x: 24, y: y, className: "heading"))
            y += 22
            let scale = max(keys.compactMap { summary.metrics[$0]?.distribution.p95 }.max() ?? 1, 1e-9)
            body.append(line(x1: labelWidth, y1: y - 6, x2: labelWidth, y2: y + Double(keys.count) * 26, className: "axis"))
            for key in keys {
                guard let d = summary.metrics[key]?.distribution else { continue }
                let p50 = max(0, d.p50) / scale * plotWidth, p95 = max(0, d.p95) / scale * plotWidth
                body.append(text(MetricLabel.title(key), x: 24, y: y + 11, className: "label"))
                body.append(bar(x: labelWidth, y: y, length: p50, className: "ddock"))
                body.append(line(x1: labelWidth + p50, y1: y + 7, x2: labelWidth + p95, y2: y + 7, className: "whisker"))
                body.append(line(x1: labelWidth + p95, y1: y + 2, x2: labelWidth + p95, y2: y + 12, className: "whisker"))
                body.append(text("\(Format.number(d.p50)) · \(Format.number(d.p95))", x: labelWidth + p95 + 8, y: y + 11, className: "value"))
                y += 26
            }
            y += 12
        }
        body.append(text("Single-machine measurement. Method and full tables: benchmarks/RESULTS.md", x: 24, y: y + 8, className: "muted"))
        let height = y + 28

        return """
        <svg xmlns="http://www.w3.org/2000/svg" width="\(Int(width))" height="\(Int(height))" viewBox="0 0 \(Int(width)) \(Int(height))" role="img" aria-labelledby="t">
        <title id="t">DDock performance summary. Values are printed next to each bar.</title>
        <style>
        svg { --surface: #fcfcfb; --ink: #0b0b0b; --ink-2: #52514e; --grid: #e1e0d9; --ddock: #2a78d6; --dock: #eb6834; }
        @media (prefers-color-scheme: dark) {
          svg { --surface: #1a1a19; --ink: #ffffff; --ink-2: #c3c2b7; --grid: #2c2c2a; --ddock: #3987e5; --dock: #d95926; }
        }
        text { font-family: -apple-system, BlinkMacSystemFont, "SF Pro Text", "Helvetica Neue", Arial, sans-serif; fill: var(--ink); }
        .title { font-size: 20px; font-weight: 600; }
        .heading { font-size: 14px; font-weight: 600; }
        .label { font-size: 13px; }
        .value { font-size: 12px; fill: var(--ink-2); font-variant-numeric: tabular-nums; }
        .muted { font-size: 12px; fill: var(--ink-2); }
        .ddock { fill: var(--ddock); }
        .dock { fill: var(--dock); }
        .axis { stroke: var(--grid); stroke-width: 1; }
        .whisker { stroke: var(--ink-2); stroke-width: 2; stroke-linecap: round; }
        </style>
        <rect width="100%" height="100%" rx="12" fill="var(--surface)"/>
        \(body.joined(separator: "\n"))
        </svg>
        """
    }

    private static func legend(x: Double, y: Double, dock: Bool) -> String {
        var parts = ["<rect x=\"\(x)\" y=\"\(y)\" width=\"10\" height=\"10\" rx=\"2\" class=\"ddock\"/>",
                     text("DDock", x: x + 16, y: y + 9, className: "value")]
        if dock {
            parts += ["<rect x=\"\(x + 70)\" y=\"\(y)\" width=\"10\" height=\"10\" rx=\"2\" class=\"dock\"/>",
                      text("macOS Dock", x: x + 86, y: y + 9, className: "value")]
        }
        return parts.joined(separator: "\n")
    }

    /// A horizontal bar, square at the baseline and rounded at its data end.
    private static func bar(x: Double, y: Double, length: Double, className: String, height: Double = 14) -> String {
        let length = max(length, 2)
        let radius = min(4, length / 2, height / 2)
        let end = x + length
        let path = "M\(x),\(y) H\(end - radius) Q\(end),\(y) \(end),\(y + radius) V\(y + height - radius) Q\(end),\(y + height) \(end - radius),\(y + height) H\(x) Z"
        return "<path d=\"\(path)\" class=\"\(className)\"/>"
    }

    private static func line(x1: Double, y1: Double, x2: Double, y2: Double, className: String) -> String {
        "<line x1=\"\(x1)\" y1=\"\(y1)\" x2=\"\(x2)\" y2=\"\(y2)\" class=\"\(className)\"/>"
    }

    private static func text(_ value: String, x: Double, y: Double, className: String) -> String {
        let escaped = value.replacingOccurrences(of: "&", with: "&amp;").replacingOccurrences(of: "<", with: "&lt;")
        return "<text x=\"\(x)\" y=\"\(y)\" class=\"\(className)\">\(escaped)</text>"
    }
}
