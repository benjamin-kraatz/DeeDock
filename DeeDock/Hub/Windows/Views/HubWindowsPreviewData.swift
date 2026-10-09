#if DEBUG
import AppKit
import SwiftUI

/// Fixed apps, windows, and drawn thumbnails for Windows tab previews. Nothing here reads the
/// workspace, asks for permissions, or touches other apps.
@MainActor
enum HubWindowsPreviewData {
    /// A source that never discovers or activates anything, for previews.
    final class InertSource: HubWindowsSource {
        func runningApps() -> [HubRunningApp] { [] }
        func discover(apps: [HarborRunningApp]) async -> HarborDiscovery {
            HarborDiscovery(windows: [], access: HarborAccess(windows: true, thumbnails: true), sessionID: UUID())
        }
        func thumbnail(_ number: CGWindowID, fittingPixels pixels: CGSize) async -> CGImage? { nil }
        func activate(_ window: HarborWindow) async {}
        func end(session: UUID) async {}
    }

    private static let appSpecs: [(id: String, name: String, symbol: String, color: NSColor)] = [
        ("com.apple.Safari", "Safari", "safari", .systemBlue),
        ("com.apple.dt.Xcode", "Xcode", "hammer", .systemIndigo),
        ("com.apple.mail", "Mail", "envelope", .systemCyan),
        ("com.apple.Notes", "Notes", "note.text", .systemYellow),
        ("com.apple.Terminal", "Terminal", "terminal", .darkGray),
    ]

    static var running: [HubRunningApp] {
        appSpecs.enumerated().map { index, spec in
            HubRunningApp(app: HarborRunningApp(id: spec.id, name: spec.name, processIdentifier: pid_t(100 + index),
                                                isHidden: false, isActive: index == 0),
                          icon: icon(symbol: spec.symbol, color: spec.color))
        }
    }

    /// (app index, title, state, capture number)
    private static let windowSpecs: [(Int, String, HarborWindowState, CGWindowID?)] = [
        (0, "Apple Developer Documentation", .visible, 11),
        (0, "DOKK – Pull Request #315", .visible, 12),
        (0, "Reading List", .minimized, nil),
        (1, "DeeDock — HubWindowsView.swift", .visible, 21),
        (2, "Inbox – 12 messages", .visible, 31),
        (3, "Groceries", .visible, 41),
        (3, "Trip ideas", .minimized, nil),
        (4, "benn — zsh — 120×36", .visible, 51),
        (4, "xcodebuild", .visible, 52),
    ]

    static var windows: [HarborWindow] {
        windowSpecs.enumerated().map { index, spec in
            let app = appSpecs[spec.0]
            return HarborWindow(id: UUID(uuidString: String(format: "00000000-0000-0000-0000-%012d", index))!,
                                appID: app.id, processIdentifier: pid_t(100 + spec.0), title: spec.1,
                                frame: CGRect(x: 80 + index * 30, y: 60 + index * 20, width: 1280, height: 820),
                                state: spec.2, token: nil, captureID: spec.3, stackOrder: index)
        }
    }

    /// Drawn stand-ins for window captures, one per capture number.
    static var thumbnails: [CGWindowID: CGImage] {
        var result: [CGWindowID: CGImage] = [:]
        for spec in windowSpecs {
            guard let number = spec.3 else { continue }
            result[number] = thumbnail(color: appSpecs[spec.0].color)
        }
        return result
    }

    /// A model filled with the sample content.
    static func model(access: HarborAccess = HarborAccess(windows: true, thumbnails: true), thumbnails: Bool = true,
                      empty: Bool = false, query: String = "", selection: String? = nil) -> HubWindowsModel {
        let model = HubWindowsModel(openRadar: {}, source: InertSource(), openAccessibilitySettings: {},
                                    openScreenRecordingSettings: {})
        model.seedForPreview(running: running, windows: empty ? [] : windows, access: access,
                             thumbnails: thumbnails ? self.thumbnails : [:], selection: selection, query: query)
        return model
    }

    private static func icon(symbol: String, color: NSColor) -> NSImage {
        NSImage(size: NSSize(width: 64, height: 64), flipped: false) { rect in
            color.setFill()
            NSBezierPath(roundedRect: rect.insetBy(dx: 4, dy: 4), xRadius: 14, yRadius: 14).fill()
            let config = NSImage.SymbolConfiguration(pointSize: 30, weight: .medium)
                .applying(.init(paletteColors: [.white]))
            if let glyph = NSImage(systemSymbolName: symbol, accessibilityDescription: nil)?
                .withSymbolConfiguration(config) {
                let size = glyph.size
                glyph.draw(in: CGRect(x: rect.midX - size.width / 2, y: rect.midY - size.height / 2,
                                      width: size.width, height: size.height))
            }
            return true
        }
    }

    private static func thumbnail(color: NSColor) -> CGImage? {
        let size = CGSize(width: 440, height: 282)
        guard let context = CGContext(data: nil, width: Int(size.width), height: Int(size.height), bitsPerComponent: 8,
                                      bytesPerRow: 0, space: CGColorSpaceCreateDeviceRGB(),
                                      bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return nil }
        // Window body, a title bar in the app's color, and a few content lines.
        context.setFillColor(NSColor(white: 0.97, alpha: 1).cgColor)
        context.fill(CGRect(origin: .zero, size: size))
        context.setFillColor(color.withAlphaComponent(0.85).cgColor)
        context.fill(CGRect(x: 0, y: size.height - 40, width: size.width, height: 40))
        context.setFillColor(NSColor(white: 0.82, alpha: 1).cgColor)
        for line in 0..<6 {
            let width = size.width * [0.8, 0.55, 0.7, 0.45, 0.65, 0.5][line]
            context.fill(CGRect(x: 24, y: size.height - 76 - CGFloat(line) * 30, width: width, height: 12))
        }
        return context.makeImage()
    }
}

#Preview("Windows · thumbnails") {
    HubWindowsView(model: HubWindowsPreviewData.model(selection: "w12"))
        .frame(width: 1180, height: 582)
}

#Preview("Windows · no Screen Recording") {
    HubWindowsView(model: HubWindowsPreviewData.model(access: HarborAccess(windows: true, thumbnails: false),
                                                      thumbnails: false))
        .frame(width: 1180, height: 582)
}

#Preview("Windows · no permissions") {
    HubWindowsView(model: HubWindowsPreviewData.model(access: HarborAccess(windows: false, thumbnails: false),
                                                      thumbnails: false))
        .frame(width: 1180, height: 582)
}

#Preview("Windows · search, dark") {
    HubWindowsView(model: HubWindowsPreviewData.model(query: "term"))
        .frame(width: 1180, height: 582)
        .preferredColorScheme(.dark)
}

#Preview("Windows · empty") {
    HubWindowsView(model: HubWindowsPreviewData.model(empty: true))
        .frame(width: 1180, height: 582)
}
#endif
