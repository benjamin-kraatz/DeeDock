import SwiftUI

struct WindowWatchView: View {
    @Bindable var session: WindowWatchSession
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency

    var body: some View {
        VStack(spacing: 0) {
            ScrollView {
                VStack(alignment: .leading, spacing: 12) {
                    Label { Text(.watchTitle) } icon: { Image(systemName: session.active ? "eye.circle.fill" : "eye") }
                        .font(.headline)
                    Text(verbatim: session.title).lineLimit(2)
                    if let image = session.image {
                        WindowWatchRegionView(image: image, region: $session.region, editable: session.ready)
                            .frame(height: 210)
                        if session.finished {
                            Button(.watchShowWindow) { session.showWindow() }
                        }
                    }
                    Text(session.message).fixedSize(horizontal: false, vertical: true)
                        .accessibilityAddTraits(.updatesFrequently)
                    if let date = session.lastSample {
                        HStack { Text(.watchLastSample); Text(date, style: .time) }.font(.caption).foregroundStyle(.secondary)
                    }
                    if session.ready { setup }
                    if let message = session.sourceMessage { Text(message).font(.caption) }
                }
                .padding(16)
            }
            Divider()
            VStack(alignment: .leading, spacing: 8) {
                if session.active {
                    HStack { ProgressView().controlSize(.small); Text(.watchIndeterminate) }
                    Button(.watchStop) { session.stop() }.keyboardShortcut(".", modifiers: .command)
                }
                if session.finished {
                    Button(.watchShowSource) { session.showSource() }
                }
                Button(.watchDismiss) { session.close() }.keyboardShortcut(.cancelAction)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(12)
        }
        .background(reduceTransparency ? AnyShapeStyle(Color(nsColor: .windowBackgroundColor)) : AnyShapeStyle(.regularMaterial))
        .frame(maxWidth: .infinity)
        .frame(maxHeight: .infinity)
    }

    private var setup: some View {
        VStack(alignment: .leading, spacing: 10) {
            Button(.watchWholeWindow) { session.region = WindowWatchRegion() }
            Text(.watchRegionHelp).font(.caption)
            Grid(alignment: .leading) {
                regionControl(.watchRegionX, value: regionBinding(\.x), range: 0...0.95)
                regionControl(.watchRegionY, value: regionBinding(\.y), range: 0...0.95)
                regionControl(.watchRegionWidth, value: regionBinding(\.width), range: 0.05...1)
                regionControl(.watchRegionHeight, value: regionBinding(\.height), range: 0.05...1)
            }
            Picker(.watchCondition, selection: $session.usesPhrase) {
                Text(.watchVisibleChange).tag(false)
                Text(.watchCompletionPhrase).tag(true)
            }
            if session.usesPhrase {
                TextField(.watchPhrase, text: $session.phrase)
                Text(.watchPhraseHelp).font(.caption)
            }
            Toggle(.watchSound, isOn: $session.playSound)
            Text(.watchDeliveryHelp).font(.caption).foregroundStyle(.secondary)
            Button(.watchStart) { session.start() }
                .keyboardShortcut(.defaultAction)
                .disabled(session.usesPhrase && session.phrase.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
        }
    }

    private func regionBinding(_ keyPath: WritableKeyPath<WindowWatchRegion, Double>) -> Binding<Double> {
        Binding {
            session.region.clamped[keyPath: keyPath]
        } set: { value in
            var region = session.region.clamped
            region[keyPath: keyPath] = value
            session.region = region.clamped
        }
    }

    private func regionControl(_ label: LocalizedStringResource, value: Binding<Double>, range: ClosedRange<Double>) -> some View {
        GridRow {
            Text(label)
            Slider(value: value, in: range, step: 0.01).accessibilityLabel(Text(label))
            Text(value.wrappedValue, format: .percent.precision(.fractionLength(0))).monospacedDigit()
        }
    }
}

/// The overlay and cropping share top-left unit coordinates. Letterbox margins never enter the selection.
private struct WindowWatchRegionView: View {
    let image: CGImage
    @Binding var region: WindowWatchRegion
    let editable: Bool

    var body: some View {
        GeometryReader { geometry in
            let scale = min(geometry.size.width / Double(image.width), geometry.size.height / Double(image.height))
            let size = CGSize(width: Double(image.width) * scale, height: Double(image.height) * scale)
            let rect = region.rect
            ZStack(alignment: .topLeading) {
                Image(decorative: image, scale: 1).resizable().frame(width: size.width, height: size.height)
                Rectangle().stroke(.orange, lineWidth: 3)
                    .background(.orange.opacity(0.12))
                    .frame(width: rect.width * size.width, height: rect.height * size.height)
                    .offset(x: rect.minX * size.width, y: rect.minY * size.height)
            }
            .frame(width: size.width, height: size.height)
            .contentShape(Rectangle())
            .gesture(DragGesture(minimumDistance: 2).onChanged { value in
                guard editable else { return }
                let x = max(0, min(value.startLocation.x, value.location.x) / size.width)
                let y = max(0, min(value.startLocation.y, value.location.y) / size.height)
                region = WindowWatchRegion(x: x, y: y,
                                           width: abs(value.location.x - value.startLocation.x) / size.width,
                                           height: abs(value.location.y - value.startLocation.y) / size.height).clamped
            })
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .accessibilityLabel(Text(.watchSelectedRegion))
    }
}

#if DEBUG
#Preview("Watch setup · German") {
    WindowWatchView(session: WindowWatchSession(previewTitle: "Export", message: .watchSetupHelp, setup: true))
        .environment(\.locale, Locale(identifier: "de"))
        .frame(height: 680)
        .disabled(true)
}
#Preview("Watch capture unavailable") {
    WindowWatchView(session: WindowWatchSession(previewTitle: "Export", message: .watchPermission, setup: false))
        .frame(height: 480)
        .disabled(true)
}
#endif
