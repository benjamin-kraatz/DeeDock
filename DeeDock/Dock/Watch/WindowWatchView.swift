import AppKit
import SwiftUI

/// The watch panel: one window, one region, one condition, one result.
///
/// The panel is arranged as the watch is used — what is being watched at the top, how it is being
/// watched in the middle, and the one action that matters at the bottom. Setup controls disappear
/// once a watch runs, so a running watch reads as a single live state rather than a form with a
/// stop button attached. Nothing here samples or activates anything; every control is explicit.
struct WindowWatchView: View {
    @Bindable var session: WindowWatchSession
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.locale) private var locale
    @State private var fineTuning = false

    /// The watched app's own color carries the panel, so it is recognizably about that window.
    private var tint: Color {
        guard let icon = session.icon else { return .accentColor }
        return DockIconAccent.surface(for: icon, identity: session.appName, dark: colorScheme == .dark) ?? .accentColor
    }

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    preview
                    if session.problem { problemBanner }
                    switch session.phase {
                    case .ready: setup
                    case .watching: running
                    case .detected: result
                    case .preparing, .ended: if !session.problem { status }
                    }
                    WindowWatchExplanationView(explanation: session.explanation)
                    WindowWatchActivityView(entries: session.activity)
                    if let message = session.sourceMessage {
                        Text(message).font(.caption).foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                .padding(18)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .scrollBounceBehavior(.basedOnSize)
            Divider()
            footer
        }
        .task(id: locale.identifier) { session.explanation.refreshAvailability(locale: locale) }
        .tint(tint)
        .background(reduceTransparency ? AnyShapeStyle(Color(nsColor: .windowBackgroundColor))
                                       : AnyShapeStyle(.regularMaterial))
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .animation(.snappy(duration: 0.22), value: session.phase)
    }

    // MARK: Header

    private var header: some View {
        HStack(spacing: 12) {
            Group {
                if let icon = session.icon {
                    Image(nsImage: icon).resizable().interpolation(.high).scaledToFit()
                } else {
                    Image(systemName: "macwindow").font(.title2).foregroundStyle(.secondary)
                }
            }
            .frame(width: 34, height: 34)
            .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 1) {
                Text(verbatim: session.title.isEmpty ? session.appName : session.title)
                    .font(.system(size: 15, weight: .semibold, design: .rounded))
                    .lineLimit(1)
                    .truncationMode(.middle)
                    .accessibilityAddTraits(.isHeader)
                Text(verbatim: session.appName)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            Spacer(minLength: 8)
            statusPill
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 12)
        .background(alignment: .top) {
            LinearGradient(colors: [tint.opacity(reduceTransparency ? 0 : 0.18), .clear],
                           startPoint: .top, endPoint: .bottom)
                .allowsHitTesting(false)
                .accessibilityHidden(true)
        }
    }

    private var statusPill: some View {
        let phase = session.phase
        return HStack(spacing: 6) {
            Image(systemName: phase.symbol)
                .symbolEffect(.pulse, isActive: phase == .watching && !reduceMotion)
                .imageScale(.small)
            Text(phase.label)
        }
        .font(.caption.weight(.semibold))
        .foregroundStyle(phase.color(tint))
        .padding(.horizontal, 10)
        .padding(.vertical, 5)
        .background(phase.color(tint).opacity(0.15), in: .capsule)
        .accessibilityElement(children: .combine)
    }

    // MARK: Preview

    @ViewBuilder private var preview: some View {
        if let image = session.image {
            VStack(alignment: .leading, spacing: 8) {
                WindowWatchRegionEditor(image: image, region: $session.region, editable: session.ready,
                                        scanning: session.active, tint: session.detected ? .green : tint)
                    .frame(height: 240)
                if session.ready {
                    Text(.watchRegionDragHint)
                        .font(.caption).foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        } else {
            VStack(spacing: 10) {
                if session.phase == .preparing { ProgressView().controlSize(.small) }
                Image(systemName: "eye.slash")
                    .font(.system(size: 26))
                    .foregroundStyle(.secondary)
                if !session.problem {
                    Text(session.message)
                        .font(.callout)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .padding(20)
            .frame(maxWidth: .infinity, minHeight: 190)
            .background(.quaternary.opacity(0.4), in: .rect(cornerRadius: 14))
        }
    }

    // MARK: Setup

    private var setup: some View {
        VStack(alignment: .leading, spacing: 16) {
            WindowWatchSection(title: .watchSectionRegion, symbol: "viewfinder") {
                VStack(alignment: .leading, spacing: 10) {
                    HStack(spacing: 8) {
                        presetButton(.watchWholeWindow, region: WindowWatchRegion())
                        presetButton(.watchPresetTop, region: WindowWatchRegion(x: 0, y: 0, width: 1, height: 0.5))
                        presetButton(.watchPresetBottom, region: WindowWatchRegion(x: 0, y: 0.5, width: 1, height: 0.5))
                        presetButton(.watchPresetCenter, region: WindowWatchRegion(x: 0.25, y: 0.25, width: 0.5, height: 0.5))
                    }
                    DisclosureGroup(isExpanded: $fineTuning) {
                        Grid(alignment: .leading) {
                            regionControl(.watchRegionX, value: regionBinding(\.x), range: 0...0.95)
                            regionControl(.watchRegionY, value: regionBinding(\.y), range: 0...0.95)
                            regionControl(.watchRegionWidth, value: regionBinding(\.width), range: 0.05...1)
                            regionControl(.watchRegionHeight, value: regionBinding(\.height), range: 0.05...1)
                        }
                        .padding(.top, 6)
                    } label: {
                        Text(.watchRegionFineTune).font(.callout)
                    }
                }
            }
            WindowWatchSection(title: .watchSectionCondition, symbol: "flag.checkered") {
                VStack(alignment: .leading, spacing: 10) {
                    HStack(spacing: 10) {
                        conditionCard(title: .watchVisibleChange, help: .watchVisibleChangeHelp,
                                      symbol: "rectangle.on.rectangle.angled", phrase: false)
                        conditionCard(title: .watchCompletionPhrase, help: .watchCompletionPhraseHelp,
                                      symbol: "text.magnifyingglass", phrase: true)
                    }
                    if session.usesPhrase {
                        TextField(.watchPhrase, text: $session.phrase)
                            .textFieldStyle(.roundedBorder)
                        Text(.watchPhraseHelp)
                            .font(.caption).foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
            }
            WindowWatchSection(title: .watchSectionDelivery, symbol: "bell") {
                VStack(alignment: .leading, spacing: 16) {
                    WindowWatchExplanationSetup(explanation: session.explanation, locale: locale)

                    VStack(alignment: .leading, spacing: 6) {
                        Toggle(.watchSound, isOn: $session.playSound)
                            .toggleStyle(TrailingSwitchToggleStyle())
                        Text(.watchDeliveryHelp)
                            .font(.caption).foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
            }
        }
    }

    private func presetButton(_ label: LocalizedStringResource, region: WindowWatchRegion) -> some View {
        let selected = session.region.clamped == region.clamped
        return Button {
            session.region = region
        } label: {
            Text(label)
                .font(.caption.weight(.medium))
                .lineLimit(1)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 6)
                .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .foregroundStyle(selected ? AnyShapeStyle(tint) : AnyShapeStyle(.primary))
        .background(selected ? tint.opacity(0.16) : Color.primary.opacity(0.06), in: .rect(cornerRadius: 8))
        .overlay { RoundedRectangle(cornerRadius: 8).strokeBorder(tint.opacity(selected ? 0.5 : 0), lineWidth: 1) }
        .accessibilityAddTraits(selected ? [.isButton, .isSelected] : .isButton)
    }

    /// The two conditions state what ends a watch, so the choice is made on the evidence rule
    /// rather than on the name of the option.
    private func conditionCard(title: LocalizedStringResource, help: LocalizedStringResource,
                               symbol: String, phrase: Bool) -> some View {
        let selected = session.usesPhrase == phrase
        return Button {
            session.usesPhrase = phrase
        } label: {
            VStack(alignment: .leading, spacing: 6) {
                Image(systemName: symbol)
                    .font(.system(size: 15))
                    .foregroundStyle(selected ? AnyShapeStyle(tint) : AnyShapeStyle(.secondary))
                Text(title).font(.callout.weight(.medium)).fixedSize(horizontal: false, vertical: true)
                Text(help).font(.caption).foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(11)
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .background(selected ? tint.opacity(0.12) : Color.primary.opacity(0.05), in: .rect(cornerRadius: 11))
        .overlay { RoundedRectangle(cornerRadius: 11).strokeBorder(tint.opacity(selected ? 0.55 : 0), lineWidth: 1.5) }
        .accessibilityAddTraits(selected ? [.isButton, .isSelected] : .isButton)
    }

    // MARK: Live state and outcome

    private var running: some View {
        VStack(alignment: .leading, spacing: 12) {
            // The banner already carries a problem verbatim; repeating it here would state it twice.
            if !session.problem {
                Text(session.message)
                    .font(.callout)
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityAddTraits(.updatesFrequently)
            }
            HStack(spacing: 10) {
                if let start = session.startDate {
                    WindowWatchReading(label: .watchElapsed, tint: tint) {
                        Text(start, style: .timer).monospacedDigit()
                    }
                }
                WindowWatchReading(label: .watchLastSample, tint: tint) {
                    if let date = session.lastSample {
                        Text(date, style: .time).monospacedDigit()
                    } else {
                        Text(.watchNoChecksYet).font(.callout).foregroundStyle(.secondary)
                    }
                }
            }
            if session.checkCount > 0 {
                Text(.watchCheckCount(session.checkCount))
                    .font(.caption).foregroundStyle(.secondary).monospacedDigit()
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(tint.opacity(0.1), in: .rect(cornerRadius: 14))
        .overlay { RoundedRectangle(cornerRadius: 14).strokeBorder(tint.opacity(0.2), lineWidth: 1) }
    }

    /// The outcome states what was observed and what it does not prove; the wording carries that,
    /// so the card only has to make it impossible to miss.
    private var result: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: "checkmark.seal.fill")
                .font(.system(size: 26))
                .foregroundStyle(.green)
                .symbolEffect(.bounce, options: .nonRepeating)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 4) {
                Text(.watchStatusDetected).font(.headline)
                Text(session.message).font(.callout).fixedSize(horizontal: false, vertical: true)
                if let date = session.lastSample {
                    HStack(spacing: 4) { Text(.watchLastSample); Text(date, style: .time).monospacedDigit() }
                        .font(.caption).foregroundStyle(.secondary)
                }
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.green.opacity(0.12), in: .rect(cornerRadius: 14))
        .overlay { RoundedRectangle(cornerRadius: 14).strokeBorder(.green.opacity(0.28), lineWidth: 1) }
        .accessibilityElement(children: .combine)
    }

    private var status: some View {
        HStack(alignment: .firstTextBaseline, spacing: 9) {
            if session.phase == .preparing { ProgressView().controlSize(.small) }
            Text(session.message)
                .font(.callout)
                .fixedSize(horizontal: false, vertical: true)
                .accessibilityAddTraits(.updatesFrequently)
            Spacer(minLength: 0)
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.quaternary.opacity(0.4), in: .rect(cornerRadius: 12))
    }

    /// A problem the user can act on, in the same shape as the badge window's banners.
    private var problemBanner: some View {
        HStack(alignment: .firstTextBaseline, spacing: 9) {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(.orange)
                .accessibilityHidden(true)
            Text(session.message)
                .font(.callout)
                .fixedSize(horizontal: false, vertical: true)
                .accessibilityAddTraits(.updatesFrequently)
            Spacer(minLength: 0)
        }
        .padding(11)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.orange.opacity(0.12), in: .rect(cornerRadius: 11))
        .accessibilityElement(children: .combine)
    }

    // MARK: Footer

    private var footer: some View {
        HStack(spacing: 10) {
            if session.finished {
                if session.image != nil {
                    Button(.watchShowWindow, systemImage: "macwindow.on.rectangle") { session.showWindow() }
                }
                Button(.watchShowSource, systemImage: "arrow.up.forward.app") { session.showSource() }
            }
            Spacer(minLength: 8)
            dismissButton
            switch session.phase {
            case .ready:
                Button(.watchStart, systemImage: "eye") { session.start() }
                    .buttonStyle(.glassProminent)
                    .keyboardShortcut(.defaultAction)
                    .disabled(session.usesPhrase && session.phrase.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            case .watching:
                Button(.watchStop, systemImage: "stop.circle") { session.stop() }
                    .buttonStyle(.glassProminent)
                    .keyboardShortcut(".", modifiers: .command)
            case .preparing, .detected, .ended:
                EmptyView()
            }
        }
        .controlSize(.large)
        .padding(.horizontal, 18)
        .padding(.vertical, 12)
    }

    /// Closing is the only action every state shares, and the only one after a finished watch,
    /// which is where it carries the panel.
    @ViewBuilder private var dismissButton: some View {
        let button = Button(.watchDismiss) { session.close() }.keyboardShortcut(.cancelAction)
        if session.finished {
            button.buttonStyle(.glassProminent)
        } else {
            button
        }
    }

    // MARK: Region plumbing

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
            Text(label).font(.callout)
            Slider(value: value, in: range, step: 0.01).accessibilityLabel(Text(label))
            Text(value.wrappedValue, format: .percent.precision(.fractionLength(0)))
                .font(.callout).monospacedDigit().frame(width: 44, alignment: .trailing)
        }
    }
}

/// A titled group of controls. The symbol names the group at a glance; the title carries the meaning.
private struct WindowWatchSection<Content: View>: View {
    let title: LocalizedStringResource
    let symbol: String
    @ViewBuilder let content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 9) {
            Label { Text(title) } icon: { Image(systemName: symbol) }
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
                .accessibilityAddTraits(.isHeader)
            content
                .padding(12)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(.quaternary.opacity(0.35), in: .rect(cornerRadius: 13))
        }
    }
}

/// One labelled reading about the running watch.
private struct WindowWatchReading<Content: View>: View {
    let label: LocalizedStringResource
    let tint: Color
    @ViewBuilder let content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(label).font(.caption2).foregroundStyle(.secondary).lineLimit(2)
            content.font(.title3.weight(.medium))
        }
        .padding(10)
        .frame(maxWidth: .infinity, minHeight: 68, alignment: .topLeading)
        .background(.background.opacity(0.5), in: .rect(cornerRadius: 10))
        .accessibilityElement(children: .combine)
    }
}

private extension WindowWatchPhase {
    var symbol: String {
        switch self {
        case .preparing: "hourglass"
        case .ready: "slider.horizontal.3"
        case .watching: "eye.fill"
        case .detected: "checkmark.circle.fill"
        case .ended: "moon.zzz"
        }
    }

    var label: LocalizedStringResource {
        switch self {
        case .preparing: .watchStatusPreparing
        case .ready: .watchStatusReady
        case .watching: .watchStatusWatching
        case .detected: .watchStatusDetected
        case .ended: .watchStatusEnded
        }
    }

    func color(_ tint: Color) -> Color {
        switch self {
        case .preparing, .ended: .secondary
        case .ready, .watching: tint
        case .detected: .green
        }
    }
}

#if DEBUG
/// A deterministic stand-in for a captured window, so previews can show the region editor without
/// a capture service, a permission prompt, or live workspace state.
@MainActor private func watchPreviewImage() -> CGImage? {
    let (width, height) = (640, 400)
    guard let context = CGContext(data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0,
                                  space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)
    else { return nil }
    context.setFillColor(NSColor.controlBackgroundColor.cgColor)
    context.fill(CGRect(x: 0, y: 0, width: width, height: height))
    context.setFillColor(NSColor.systemBlue.withAlphaComponent(0.35).cgColor)
    context.fill(CGRect(x: 0, y: height - 48, width: width, height: 48))
    context.setFillColor(NSColor.labelColor.withAlphaComponent(0.18).cgColor)
    for row in 0..<9 {
        context.fill(CGRect(x: 32, y: height - 110 - row * 28, width: row.isMultiple(of: 3) ? 420 : 280, height: 12))
    }
    return context.makeImage()
}

@MainActor private func watchPreviewSession(message: LocalizedStringResource, setup: Bool,
                                            configure: (WindowWatchSession) -> Void = { _ in }) -> WindowWatchSession {
    let session = WindowWatchSession(previewTitle: "Export – annual-report.pdf", message: message, setup: setup)
    session.image = watchPreviewImage()
    configure(session)
    return session
}

#Preview("Setup") {
    WindowWatchView(session: watchPreviewSession(message: .watchSetupHelp, setup: true) {
        $0.region = WindowWatchRegion(x: 0.08, y: 0.55, width: 0.5, height: 0.3)
    })
    .frame(width: 520, height: 780)
}

#Preview("Setup · German") {
    WindowWatchView(session: watchPreviewSession(message: .watchSetupHelp, setup: true))
        .environment(\.locale, Locale(identifier: "de"))
        .frame(width: 520, height: 780)
}

#Preview("Watching") {
    WindowWatchView(session: watchPreviewSession(message: .watchWatching, setup: false) {
        $0.finished = false
        $0.active = true
        $0.startDate = Date(timeIntervalSinceNow: -184)
        $0.lastSample = Date()
        $0.checkCount = 61
        $0.region = WindowWatchRegion(x: 0.1, y: 0.1, width: 0.6, height: 0.45)
    })
    .frame(width: 520, height: 780)
}

#Preview("Detected") {
    WindowWatchView(session: watchPreviewSession(message: .watchChangeDetected, setup: false) {
        $0.detected = true
        $0.lastSample = Date()
    })
    .frame(width: 520, height: 780)
}

#Preview("Capture unavailable") {
    WindowWatchView(session: watchPreviewSession(message: .watchPermission, setup: false) {
        $0.image = nil
        $0.problem = true
    })
    .frame(width: 520, height: 600)
}
#endif
