#if DEBUG
import SwiftUI

/// An inspection slider exposes intermediate silhouettes in the same AppKit renderer as DDock.
private struct LauncherLiquidGlassPreview: View {
    @State private var progress = 0.25

    var body: some View {
        VStack {
            LauncherLiquidGlassPreviewSurface(progress: progress)
                .frame(width: 640, height: 470)
            Slider(value: $progress, in: 0...1) { Text(.launcherTitle) }
            Text(progress, format: .percent.precision(.fractionLength(0)))
                .monospacedDigit()
        }
        .padding(24)
    }
}

private struct LauncherLiquidGlassPreviewSurface: NSViewRepresentable {
    let progress: Double

    private var geometry: LauncherLiquidGeometry {
        LauncherLiquidGeometry(
            dock: CGRect(x: 100, y: 390, width: 440, height: 60),
            destination: CGRect(x: 60, y: 30, width: 520, height: 420),
            dockRadius: 22
        )
    }

    private var dock: AnyView {
        AnyView(HStack(spacing: 24) {
            ForEach(["square.grid.3x3.fill", "folder.fill", "safari.fill", "envelope.fill", "gearshape.fill"], id: \.self) {
                Image(systemName: $0).font(.system(size: 30)).foregroundStyle(.blue)
            }
        }.frame(width: 440, height: 60))
    }

    private var launcher: AnyView {
        AnyView(VStack(spacing: 28) {
            Image(systemName: "magnifyingglass").font(.title)
            ForEach(0..<3) { _ in
                HStack(spacing: 48) {
                    ForEach(["folder.fill", "safari.fill", "envelope.fill", "gearshape.fill"], id: \.self) {
                        Image(systemName: $0).font(.system(size: 38)).foregroundStyle(.blue)
                    }
                }
            }
        }.frame(width: 520, height: geometry.destination.height))
    }

    func makeNSView(context: Context) -> LauncherLiquidGlassView {
        LauncherLiquidGlassView(geometry: geometry, dock: dock, launcher: launcher)
    }

    func updateNSView(_ view: LauncherLiquidGlassView, context: Context) {
        view.update(geometry: geometry, dock: dock, launcher: launcher,
                    dockCanvas: geometry.dock, expanded: true, reduceMotion: true, reduceTransparency: false)
        view.inspect(progress: progress)
    }

    static func dismantleNSView(_ view: LauncherLiquidGlassView, coordinator: ()) { view.stop() }
}

#Preview("Liquid glass silhouette") { LauncherLiquidGlassPreview() }
#endif
