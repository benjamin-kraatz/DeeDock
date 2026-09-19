import AppKit
import SwiftUI

/// Keeps hosted controls at one layout size. A separate layer transports the rendered content
/// while native glass changes shape, without introducing fractional text-field constraints.
final class LauncherGlassContentView: NSView {
    private let host: NSHostingView<AnyView>
    private let transport = NSView()
    private var viewportSize = CGSize.zero
    private var presentationScale: CGFloat = 1
    private var presentationOpacity: Float = 1
    var contentSize = CGSize.zero {
        didSet { if contentSize != oldValue { configureLayout() } }
    }
    var contentOffset: CGPoint? {
        didSet { if contentOffset != oldValue { configureLayout() } }
    }
    override var isFlipped: Bool { true }

    init(rootView: AnyView) {
        host = NSHostingView(rootView: rootView)
        super.init(frame: .zero)
        wantsLayer = true
        transport.wantsLayer = true
        host.sizingOptions = []
        addSubview(transport)
        transport.addSubview(host)
        transport.layer?.anchorPoint = .zero
    }

    required init?(coder: NSCoder) { nil }

    func update(rootView: AnyView) { host.rootView = rootView }

    /// Called only when the presentation's endpoint layout changes, never by the display link.
    private func configureLayout() {
        let rect = CGRect(origin: contentOffset ?? .zero, size: contentSize)
        if transport.frame != rect { transport.frame = rect }
        let hostedFrame = CGRect(origin: .zero, size: contentSize)
        if host.frame != hostedFrame { host.frame = hostedFrame }
    }

    /// Changes only compositing properties. During travel, controls are noninteractive; at the
    /// destination the transform is identity, so native hit testing and the field editor agree.
    func present(viewport: CGSize, scale: CGFloat, opacity: CGFloat) {
        viewportSize = viewport
        presentationScale = scale
        presentationOpacity = Float(opacity)
        applyTransform()
    }

    override func layout() {
        super.layout()
        applyTransform()
    }

    private func applyTransform() {
        let origin = contentOffset ?? CGPoint(
            x: (viewportSize.width - contentSize.width * presentationScale) / 2,
            y: (viewportSize.height - contentSize.height * presentationScale) / 2
        )
        let base = contentOffset ?? .zero
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        let transform = CGAffineTransform(
            a: presentationScale, b: 0, c: 0, d: presentationScale,
            tx: origin.x - base.x, ty: origin.y - base.y
        )
        if transport.layer?.affineTransform() != transform {
            transport.layer?.setAffineTransform(transform)
        }
        if transport.layer?.opacity != presentationOpacity {
            transport.layer?.opacity = presentationOpacity
        }
        CATransaction.commit()
    }
}
