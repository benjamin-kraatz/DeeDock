#!/usr/bin/env python3
"""Measure the production metadata ranker against synthetic, in-memory stores. Does not launch DDock."""
import pathlib
import subprocess
import tempfile

root = pathlib.Path(__file__).resolve().parents[1]
with tempfile.TemporaryDirectory(prefix="dee20-benchmark-") as directory:
    work = pathlib.Path(directory)
    subprocess.run(["xcrun", "xcstringstool", "generate-symbols", "--language", "swift",
                    "--output-directory", str(work), str(root / "DeeDock/Resources/Localizable.xcstrings")], check=True)
    # Compile the real value declarations without pulling in native capture services.
    context = (root / "DeeDock/Dock/WindowContext/WindowContextCaptureService.swift").read_text()
    (work / "WindowContextValues.swift").write_text(context.split("nonisolated enum WindowContextCaptureError")[0])
    (work / "Benchmark.swift").write_text(r'''
import Foundation

@main struct Benchmark {
    static func main() async {
        let apps = (0..<10_000).map { index in
            LauncherApplication(reference: ApplicationReference(bundleIdentifier: "benchmark.app.\(index)",
                url: URL(fileURLWithPath: "/Applications/Invoice Tool \(index).app"), name: "Invoice Tool \(index)"),
                aliases: ["Rechnung", "Büro", "Office"])
        }
        let capsules = (0..<30).map { index in
            SessionCapsule(title: "Invoice capsule \(index)", summary: String(repeating: "Invoice review work ", count: 300),
                unfinishedTasks: ["Check invoice"], windows: [], note: "Next invoice", breadcrumb: SessionCapsuleBreadcrumb(nextStep: "Send invoice"))
        }
        let shelf = (0..<50).map { index in
            ShelfItem(url: URL(fileURLWithPath: "/benchmark/invoice-\(index).pdf"), name: "invoice-\(index).pdf", bookmarkData: Data())
        }
        let shortcuts = (0..<30).map { ActionTile(id: UUID(), name: "Invoice Shortcut \($0)") }
        let modes = (0..<100).map { LauncherSearchName(id: UUID(), name: "Invoice Mode \($0)") }
        let windows = (0..<200).map { index in
            WindowSearchSource(id: UUID(), applicationName: "Invoice App", processIdentifier: 0, launchDate: nil,
                window: ApplicationWindowSummary(token: ApplicationWindowToken(sessionID: UUID(), id: UUID()),
                    processIdentifier: 0, title: "Invoice window \(index)", frame: .zero, isMinimized: false, isMain: false), candidate: nil)
        }
        print("Dataset: 10000 apps, 200 windows, 30 capsules, 50 Shelf files, 30 Shortcuts, 100 modes. In-memory metadata only.")
        for query in ["invoice", "Invoice Tool 9999", "invocie", "büro", "no-such-result"] {
            let input = LauncherSearchInput(query: query, kind: .all, applications: apps, capsules: capsules,
                shelf: shelf, shortcuts: shortcuts, modes: modes, windowRevision: UUID())
            _ = await LauncherSearchIndex.results(input, windows: windows)
            var milliseconds: [Double] = []
            var count = 0
            for _ in 0..<20 {
                let start = ContinuousClock.now
                count = await LauncherSearchIndex.results(input, windows: windows).count
                let duration = start.duration(to: .now).components
                milliseconds.append(Double(duration.seconds) * 1_000 + Double(duration.attoseconds) / 1e15)
            }
            milliseconds.sort()
            print("\(query): \(count) results; median \(String(format: "%.2f", milliseconds[10])) ms; p95 \(String(format: "%.2f", milliseconds[18])) ms; max \(String(format: "%.2f", milliseconds[19])) ms")
        }
    }
}
''')
    sources = [
        "DeeDock/Dock/Models/ApplicationReference.swift", "DeeDock/Dock/Models/ApplicationMenu.swift",
        "DeeDock/Dock/Capsules/SessionCapsuleModels.swift", "DeeDock/Dock/Shelf/ShelfItem.swift",
        "DeeDock/Dock/Actions/ActionTile.swift", "DeeDock/Dock/Search/WindowSearchModels.swift",
        "DeeDock/Dock/Search/WindowSearchIndex.swift", "DeeDock/Launcher/Models/LauncherApplication.swift",
        "DeeDock/Launcher/Models/LauncherOptions.swift", "DeeDock/Launcher/Search/LauncherSearchResult.swift", "DeeDock/Launcher/Search/LauncherSearchIndex.swift",
    ]
    binary = work / "benchmark"
    subprocess.run(["xcrun", "swiftc", "-O", "-parse-as-library", "-swift-version", "5", "-o", str(binary)]
                   + [str(root / source) for source in sources]
                   + [str(path) for path in work.glob("*.swift")], check=True)
    subprocess.run([str(binary)], check=True)
