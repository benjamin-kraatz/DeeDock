import AppKit
import SwiftUI
import UniformTypeIdentifiers

/// The system folder icon, rasterized once at 2×, for the panel's rows.
/// Uses the generic folder icon, never a folder's custom icon, so no live workspace state is read.
enum VaporFolderSprite {
    static let image: Image = {
        let side = 96
        let icon = NSWorkspace.shared.icon(for: .folder)
        guard let context = CGContext(data: nil, width: side, height: side, bitsPerComponent: 8, bytesPerRow: 0,
                                      space: CGColorSpace(name: CGColorSpace.sRGB) ?? CGColorSpaceCreateDeviceRGB(),
                                      bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else {
            return Image(nsImage: icon)
        }
        context.interpolationQuality = .high
        let graphics = NSGraphicsContext(cgContext: context, flipped: false)
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = graphics
        icon.draw(in: CGRect(x: 0, y: 0, width: side, height: side))
        NSGraphicsContext.restoreGraphicsState()
        guard let image = context.makeImage() else { return Image(nsImage: icon) }
        return Image(decorative: image, scale: 2)
    }()
}

/// The folders inside the orb and their particles, drawn from ``VaporPileEngine`` in a canvas
/// that covers the orb's whole window.
///
/// Bodies are clipped to the glass; steam and sparks are not, so steam can rise out of the top
/// of the orb into the window's margin, fading before it reaches the window's edge.
///
/// The timeline is paused whenever the engine sleeps, so a settled pile draws once and then
/// costs nothing until something changes.
struct VaporOrbPileCanvas: View {
    let engine: VaporPileEngine
    let palette: VaporOrbPalette

    var body: some View {
        TimelineView(.animation(paused: !engine.isRunning)) { timeline in
            Canvas { context, size in
                let world = engine.frame(at: timeline.date)
                Self.draw(world, in: &context, size: size, palette: palette)
            }
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }

    private static func draw(_ world: VaporPhysicsWorld, in context: inout GraphicsContext, size: CGSize,
                             palette: VaporOrbPalette) {
        let center = CGPoint(x: size.width / 2, y: size.height / 2)
        if !world.bodies.isEmpty {
            let icon = context.resolve(VaporFolderGlyph.image)
            let glass = world.innerRadius + 1
            context.drawLayer { layer in
                layer.clip(to: Path(ellipseIn: CGRect(x: center.x - glass, y: center.y - glass,
                                                      width: glass * 2, height: glass * 2)))
                for body in world.bodies {
                    var copy = layer
                    copy.opacity = min(max(body.alpha, 0), 1)
                    copy.translateBy(x: center.x + body.position.x, y: center.y + body.position.y)
                    copy.rotate(by: .radians(body.angle))
                    copy.scaleBy(x: body.scale, y: body.scale)
                    copy.draw(icon, in: VaporFolderGlyph.rect(artWidth: VaporPileSizing.iconWidth(radius: body.radius)))
                }
            }
        }
        guard !world.particles.isEmpty else { return }
        // Steam is drawn slightly soft, so it reads as vapour rather than dots; sparks stay crisp.
        context.drawLayer { layer in
            layer.addFilter(.blur(radius: 0.7))
            draw(world.particles.filter { $0.kind == .steam }, in: &layer, center: center, color: palette.steam, strength: 0.8)
        }
        draw(world.particles.filter { $0.kind == .spark }, in: &context, center: center, color: VaporOrbPalette.spark, strength: 1)
    }

    private static func draw(_ particles: [VaporParticle], in context: inout GraphicsContext, center: CGPoint,
                             color: Color, strength: Double) {
        for particle in particles {
            let x = center.x + particle.position.x, y = center.y + particle.position.y
            // Steam that drifts near the window's top edge fades out instead of being cut off.
            let edgeFade = min(max((y - particle.radius) / 24, 0), 1)
            let opacity = particle.opacity * strength * edgeFade
            guard opacity > 0.01 else { continue }
            let r = particle.radius
            context.fill(Path(ellipseIn: CGRect(x: x - r, y: y - r, width: r * 2, height: r * 2)),
                         with: .color(color.opacity(opacity)))
        }
    }
}
