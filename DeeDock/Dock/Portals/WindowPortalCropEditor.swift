import SwiftUI

/// Edits the retained full-window frame. Confirmation binds the selection to that frame's source size.
struct WindowPortalCropEditor: View {
    let state: WindowPortalState
    @State private var region = NormalizedWindowRegion()

    var body: some View {
        VStack(spacing: 12) {
            Text(.portalCrop).font(.headline)
            if let image = state.image {
                GeometryReader { geometry in
                    // Both SwiftUI image and gesture coordinates have a top-left origin. The outer
                    // centered frame supplies letterboxing; gestures belong only to the inner image.
                    let scale = min(geometry.size.width / Double(image.width), geometry.size.height / Double(image.height))
                    let size = CGSize(width: Double(image.width) * scale, height: Double(image.height) * scale)
                    let rect = region.rect
                    Image(decorative: image, scale: 1).resizable()
                        .frame(width: size.width, height: size.height)
                        .overlay(alignment: .topLeading) {
                            Rectangle().strokeBorder(.orange, lineWidth: 3)
                                .background(.orange.opacity(0.12))
                                .frame(width: rect.width * size.width, height: rect.height * size.height)
                                .offset(x: rect.minX * size.width, y: rect.minY * size.height)
                                .allowsHitTesting(false)
                        }
                        .contentShape(.rect)
                        .gesture(DragGesture(minimumDistance: 2).onChanged { value in
                            guard size.width > 0, size.height > 0 else { return }
                            let x = min(max(value.startLocation.x / size.width, 0), 1)
                            let y = min(max(value.startLocation.y / size.height, 0), 1)
                            let endX = min(max(value.location.x / size.width, 0), 1)
                            let endY = min(max(value.location.y / size.height, 0), 1)
                            region = NormalizedWindowRegion(x: min(x, endX), y: min(y, endY),
                                width: abs(x - endX), height: abs(y - endY)).clamped
                        })
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
                .frame(height: 200)
                .accessibilityHidden(true)
                Text(.portalCropHelp).font(.caption)
                control(.watchRegionX, keyPath: \.x, range: 0...0.95)
                control(.watchRegionY, keyPath: \.y, range: 0...0.95)
                control(.watchRegionWidth, keyPath: \.width, range: 0.05...1)
                control(.watchRegionHeight, keyPath: \.height, range: 0.05...1)
            }
            HStack {
                Button(.portalWholeWindow) { region = NormalizedWindowRegion() }
                Spacer()
                Button(.portalCropCancel) { state.editingCrop = false }.keyboardShortcut(.cancelAction)
                Button(.portalCropConfirm) { state.applyCrop(region) }
                    .keyboardShortcut(.defaultAction)
                    .disabled(state.image == nil || state.source.frame == nil)
            }
        }
        .padding(20)
        .frame(width: 440)
        .onAppear { region = state.crop }
    }

    private func control(_ label: LocalizedStringResource,
                         keyPath: WritableKeyPath<NormalizedWindowRegion, Double>,
                         range: ClosedRange<Double>) -> some View {
        let binding = Binding<Double>(get: { region.clamped[keyPath: keyPath] }, set: {
            region[keyPath: keyPath] = $0
            region = region.clamped
        })
        return HStack {
            Text(label)
            Spacer()
            Text(binding.wrappedValue, format: .percent.precision(.fractionLength(0)))
                .monospacedDigit()
            Stepper(label, value: binding, in: range, step: 0.01).labelsHidden()
        }
    }
}
