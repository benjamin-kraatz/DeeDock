import SwiftUI
import UniformTypeIdentifiers

/// The markup window's content: header, tool palette, stage, action bar, and notices.
///
/// The chrome fades and settles in while the picture flies from the enlarged preview, so the eye
/// follows one object and the controls arrive around it. Reduce Motion replaces both with a fade.
struct WindowMarkupEditorView: View {
    let session: WindowMarkupSession
    /// Where the picture starts, in this window's top-left-origin space; `nil` fades in place.
    var origin: CGRect? = nil
    var reduceTransparencyOverride: Bool? = nil
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var appeared = false

    private var opaque: Bool { reduceTransparencyOverride ?? reduceTransparency }

    var body: some View {
        ZStack(alignment: .top) {
            background
            VStack(spacing: 0) {
                WindowMarkupHeader(session: session)
                    .opacity(appeared ? 1 : 0)
                    .offset(y: appeared || reduceMotion ? 0 : -8)
                HStack(alignment: .center, spacing: 0) {
                    WindowMarkupToolPalette(document: session.document, tint: session.tint, opaque: opaque)
                        .padding(.leading, 14)
                        .opacity(appeared ? 1 : 0)
                        .offset(x: appeared || reduceMotion ? 0 : -12)
                    WindowMarkupStageView(session: session, origin: origin, appeared: $appeared)
                        .padding(.horizontal, 18)
                        .padding(.vertical, 6)
                        .padding(.trailing, 44)
                }
                WindowMarkupActionBar(session: session, opaque: opaque)
                    .opacity(appeared ? 1 : 0)
                    .offset(y: appeared || reduceMotion ? 0 : 10)
            }
            notice
        }
        .animation(reduceMotion ? .easeOut(duration: 0.2) : .spring(duration: 0.55, bounce: 0.12).delay(0.05), value: appeared)
        .frame(minWidth: WindowMarkupLayout.minimumSize.width, minHeight: WindowMarkupLayout.minimumSize.height)
        .tint(session.tint)
        .onAppear {
            // The first frame renders the picture at its origin; animating afterwards is the flight.
            Task { @MainActor in appeared = true }
        }
    }

    private var background: some View {
        ZStack {
            if opaque {
                Color(nsColor: .windowBackgroundColor)
            } else {
                Rectangle().fill(.regularMaterial)
            }
            LinearGradient(colors: [session.tint.opacity(opaque ? 0.1 : 0.22), .clear, session.tint.opacity(0.06)],
                           startPoint: .top, endPoint: .bottom)
            // The stage reads as a darker well so the picture's own edges stay visible on light windows.
            Color.black.opacity(0.08)
                .padding(.top, WindowMarkupLayout.headerHeight)
                .padding(.bottom, WindowMarkupLayout.footerHeight)
        }
        .ignoresSafeArea()
    }

    @ViewBuilder private var notice: some View {
        if let notice = session.notice {
            Label {
                Text(notice.message)
            } icon: {
                Image(systemName: notice.symbol)
                    .foregroundStyle(notice.kind == .success ? AnyShapeStyle(.green) : AnyShapeStyle(.orange))
            }
            .font(.callout.weight(.medium))
            .padding(.horizontal, 14)
            .padding(.vertical, 8)
            .modifier(WindowMarkupChrome(opaque: opaque, radius: 20))
            .padding(.top, WindowMarkupLayout.headerHeight + 8)
            .transition(.move(edge: .top).combined(with: .opacity))
            .accessibilityAddTraits(.isStaticText)
        }
    }
}

#if DEBUG
/// Synthetic window artwork. Previews never capture the user's windows.
private func windowMarkupPreviewImage(width: Int, height: Int) -> CGImage? {
    guard let context = CGContext(data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0,
                                  space: CGColorSpaceCreateDeviceRGB(),
                                  bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue) else { return nil }
    let w = CGFloat(width), h = CGFloat(height)
    context.setFillColor(CGColor(gray: 0.97, alpha: 1))
    context.fill(CGRect(x: 0, y: 0, width: w, height: h))
    context.setFillColor(CGColor(red: 0.2, green: 0.4, blue: 0.7, alpha: 1))
    context.fill(CGRect(x: 0, y: h * 0.9, width: w, height: h * 0.1))
    context.setFillColor(CGColor(gray: 0.7, alpha: 1))
    for row in 0..<10 {
        context.fill(CGRect(x: w * 0.06, y: h * (0.8 - CGFloat(row) * 0.07), width: w * (0.7 - CGFloat(row) * 0.04),
                            height: h * 0.02))
    }
    return context.makeImage()
}

/// A preview session with no capture service behind it, so nothing is captured or written.
@MainActor private func windowMarkupPreviewSession(marks: Bool, framed: Bool = false, crop: Bool = false,
                                                   liveText: Bool = false) -> WindowMarkupSession {
    let window = ApplicationWindowSummary(token: ApplicationWindowToken(sessionID: UUID(), id: UUID()),
                                          processIdentifier: 42, title: "Quarterly Report.pages",
                                          frame: CGRect(x: 0, y: 0, width: 960, height: 600),
                                          isMinimized: true, isMain: true)
    let request = WindowMarkupRequest(window: window, appName: "Pages",
                                      appIcon: NSWorkspace.shared.icon(for: .pdf),
                                      preview: windowMarkupPreviewImage(width: 1920, height: 1200), origin: nil,
                                      visibleFrame: CGRect(x: 0, y: 0, width: 1512, height: 944), backingScale: 2,
                                      settings: .defaults, shelfAvailable: true)
    let session = WindowMarkupSession(request: request, thumbnails: WindowMarkupPreviewThumbnails())
    session.stageOnShelf = { _ in 0 }
    let document = session.document
    if marks {
        document.commit(WindowMarkupElement(shape: .stroke(points: [CGPoint(x: 200, y: 200), CGPoint(x: 420, y: 260),
                                                                    CGPoint(x: 600, y: 210)]), color: .red, weight: .regular))
        document.commit(WindowMarkupElement(shape: .highlight(points: [CGPoint(x: 120, y: 420), CGPoint(x: 900, y: 420)]),
                                            color: .yellow, weight: .bold))
        document.commit(WindowMarkupElement(shape: .arrow(from: CGPoint(x: 1300, y: 700), to: CGPoint(x: 1000, y: 500)),
                                            color: .blue, weight: .regular))
        document.commit(WindowMarkupElement(shape: .rectangle(CGRect(x: 100, y: 560, width: 700, height: 160)),
                                            color: .green, weight: .regular))
        document.commit(WindowMarkupElement(shape: .text("Needs a second look", origin: CGPoint(x: 1000, y: 760)),
                                            color: .purple, weight: .regular))
        document.commit(WindowMarkupElement(shape: .badge(number: 1, center: CGPoint(x: 160, y: 160)), color: .red,
                                            weight: .regular))
        document.commit(WindowMarkupElement(shape: .badge(number: 2, center: CGPoint(x: 1240, y: 980)), color: .red,
                                            weight: .regular))
        document.commit(WindowMarkupElement(shape: .redact(CGRect(x: 120, y: 880, width: 560, height: 120), style: .solid),
                                            color: .black, weight: .regular))
    }
    document.framed = framed
    document.liveText = liveText
    if crop { document.crop = CGRect(x: 80, y: 120, width: 1400, height: 800); document.tool = .crop }
    return session
}

/// Returns nothing, so previews show the "preview only" state without ScreenCaptureKit.
private actor WindowMarkupPreviewThumbnails: WindowThumbnailServicing {
    func discover(processes: [ApplicationProcessSnapshot], sessionID: UUID) async throws -> [ApplicationWindowSummary] { [] }
    func capture(_ windows: [ApplicationWindowSummary], size: CGSize) async -> [ApplicationWindowToken: CGImage] { [:] }
    func capture(_ window: ApplicationWindowSummary, fittingPixels pixels: CGSize) async -> CGImage? { nil }
    func stop() {}
}

#Preview("Marked up") {
    WindowMarkupEditorView(session: windowMarkupPreviewSession(marks: true))
        .frame(width: 1100, height: 720)
}
#Preview("Cropping, framed, dark") {
    WindowMarkupEditorView(session: windowMarkupPreviewSession(marks: true, framed: true, crop: true))
        .preferredColorScheme(.dark)
        .frame(width: 1100, height: 720)
}
#Preview("Empty, narrow, German, opaque") {
    WindowMarkupEditorView(session: windowMarkupPreviewSession(marks: false), reduceTransparencyOverride: true)
        .environment(\.locale, Locale(identifier: "de"))
        .frame(width: 700, height: 480)
}
#endif
