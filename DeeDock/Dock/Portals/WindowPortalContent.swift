import SwiftUI

/// Presents a viewport of the sole retained image without allocating a second cropped bitmap.
struct WindowPortalContent: View {
    let state: WindowPortalState
    let image: CGImage
    @State private var dragOrigin: CGPoint?

    var body: some View {
        GeometryReader { geometry in
            let rect = state.viewport
            let pixelWidth = Double(image.width) * rect.width
            let pixelHeight = Double(image.height) * rect.height
            let fit = min(geometry.size.width / pixelWidth, geometry.size.height / pixelHeight)
            let size = CGSize(width: pixelWidth * fit, height: pixelHeight * fit)
            // Image pixels and SwiftUI layout use top-left coordinates here. No AppKit global
            // points or backing-scale multiplication belongs in this presentation conversion.
            Image(decorative: image, scale: 1).resizable().interpolation(.high)
                .frame(width: Double(image.width) * fit, height: Double(image.height) * fit)
                .offset(x: -rect.minX * Double(image.width) * fit,
                        y: -rect.minY * Double(image.height) * fit)
                .frame(width: size.width, height: size.height, alignment: .topLeading)
                .clipped()
                .contentShape(.rect)
                .gesture(DragGesture().onChanged { value in
                    guard state.zoom > 1, size.width > 0, size.height > 0 else { return }
                    let origin = dragOrigin ?? CGPoint(x: state.panX, y: state.panY)
                    dragOrigin = origin
                    let extra = state.zoom - 1
                    state.panX = min(max(origin.x - value.translation.width / (size.width * extra), 0), 1)
                    state.panY = min(max(origin.y - value.translation.height / (size.height * extra), 0), 1)
                }.onEnded { _ in dragOrigin = nil })
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }
}

/// Standard sliders expose zoom and bounded pan to keyboard and VoiceOver users.
struct WindowPortalViewportControls: View {
    @Bindable var state: WindowPortalState

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Slider(value: $state.zoom, in: 1...4, step: 0.25) { Text(.portalZoom) }
            Text(state.zoom, format: .number.precision(.fractionLength(2)))
            Slider(value: $state.panX, in: 0...1, step: 0.05) { Text(.portalPanHorizontal) }
                .disabled(state.zoom == 1)
            Slider(value: $state.panY, in: 0...1, step: 0.05) { Text(.portalPanVertical) }
                .disabled(state.zoom == 1)
            Button(.portalResetCrop) { state.resetZoom() }
        }.padding().frame(width: 260)
    }
}
