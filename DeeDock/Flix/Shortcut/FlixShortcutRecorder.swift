import AppKit
import Observation
import SwiftUI

/// Listens for one key combination while the recorder is active.
///
/// A local key monitor exists only between ``begin()`` and ``end()``; DOKK's own global shortcut is
/// paused meanwhile (through `recordingChanged`) so pressing the current combination records it
/// instead of opening the panel. Escape cancels. Modifier-only presses update the live preview.
@MainActor @Observable
final class FlixShortcutRecorderModel {
    private(set) var isRecording = false
    /// The modifiers held right now, for the live "⌃⌥…" preview.
    private(set) var liveModifiers: FlixShortcutCombo.Modifiers = []
    /// Why the last press was refused, shown under the recorder.
    private(set) var refusal: LocalizedStringResource?

    @ObservationIgnored var recorded: ((FlixShortcutCombo) -> Void)?
    @ObservationIgnored var recordingChanged: ((Bool) -> Void)?
    @ObservationIgnored private var monitor: Any?

    func begin() {
        guard !isRecording else { return }
        isRecording = true
        refusal = nil
        liveModifiers = []
        recordingChanged?(true)
        monitor = NSEvent.addLocalMonitorForEvents(matching: [.keyDown, .flagsChanged]) { [weak self] event in
            guard let self else { return event }
            return handle(event) ? nil : event
        }
    }

    func end() {
        guard isRecording else { return }
        isRecording = false
        liveModifiers = []
        if let monitor { NSEvent.removeMonitor(monitor) }
        monitor = nil
        recordingChanged?(false)
    }

    /// - Returns: True when the event belonged to the recorder.
    private func handle(_ event: NSEvent) -> Bool {
        let modifiers = FlixShortcutCombo.Modifiers(event.modifierFlags)
        if event.type == .flagsChanged {
            liveModifiers = modifiers
            return true
        }
        if event.keyCode == 53, modifiers.isEmpty { end(); return true }
        switch FlixShortcutCombo.recording(keyCode: event.keyCode, modifiers: modifiers) {
        case .incomplete:
            return true
        case .needsModifier:
            refusal = .flixShortcutNeedsModifier
            return true
        case .combo(let combo):
            if let conflict = FlixShortcutConflict.conflict(for: combo), conflict.refuses {
                refusal = conflict.message
                return true
            }
            refusal = nil
            recorded?(combo)
            end()
            return true
        }
    }

    isolated deinit { end() }
}

/// The shortcut field in Settings: the combination as keycaps; click to record a new one.
struct FlixShortcutRecorder: View {
    let combo: FlixShortcutCombo
    let model: FlixShortcutRecorderModel
    let reset: () -> Void

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: FlixStyle.controlRadius, style: .continuous)
        HStack(spacing: 6) {
            Button {
                model.isRecording ? model.end() : model.begin()
            } label: {
                HStack(spacing: 3) {
                    if model.isRecording {
                        if model.liveModifiers.isEmpty {
                            Text(.flixShortcutRecording).foregroundStyle(.secondary)
                        } else {
                            FlixKeycaps(keys: model.liveModifiers.symbols.map(String.init))
                        }
                    } else {
                        FlixKeycaps(keys: combo.modifiers.symbols.map(String.init) + [FlixShortcutCombo.keyName(for: combo.keyCode)])
                    }
                }
                .font(.system(size: 12))
                .padding(.horizontal, 8)
                .frame(minWidth: 110, minHeight: 26)
                .background(FlixStyle.field, in: shape)
                .overlay(shape.strokeBorder(model.isRecording ? Color.accentColor : FlixStyle.outline,
                                            lineWidth: model.isRecording ? 1.5 : 0.5))
                // A soft accent halo while recording, like a focused field.
                .overlay(shape.inset(by: -2.5).strokeBorder(Color.accentColor.opacity(model.isRecording ? 0.25 : 0), lineWidth: 2.5))
                .contentShape(.rect)
                .contentShape(.focusEffect, shape)
                .animation(FlixMotion.hover, value: model.isRecording)
            }
            .buttonStyle(.plain)
            .accessibilityLabel(Text(.flixShortcutTitle))
            .accessibilityValue(Text(verbatim: model.isRecording ? String(localized: .flixShortcutRecording)
                                                                 : combo.displayString))
            .accessibilityHint(Text(.flixShortcutRecordHint))
            if combo != .default, !model.isRecording {
                Button(action: reset) { Image(systemName: "arrow.counterclockwise") }
                    .buttonStyle(.borderless)
                    .help(Text(.flixShortcutReset))
                    .accessibilityLabel(Text(.flixShortcutReset))
            }
        }
        .onDisappear { model.end() }
    }
}

/// Keys drawn as small caps, as the mockup's `.kc`.
struct FlixKeycaps: View {
    let keys: [String]

    var body: some View {
        HStack(spacing: 3) {
            ForEach(Array(keys.enumerated()), id: \.offset) { _, key in
                Text(verbatim: key)
                    .font(.system(size: 11, weight: .medium))
                    .frame(minWidth: 18, minHeight: 18)
                    .padding(.horizontal, 3)
                    .background(FlixStyle.key, in: RoundedRectangle(cornerRadius: 4, style: .continuous))
                    .overlay(RoundedRectangle(cornerRadius: 4, style: .continuous).strokeBorder(FlixStyle.outline, lineWidth: 0.5))
                    .shadow(color: Color.primary.opacity(0.15), radius: 0, y: 1)
            }
        }
        .accessibilityHidden(true)
    }
}

#if DEBUG
#Preview("Shortcut recorder") {
    VStack(alignment: .trailing, spacing: 12) {
        FlixShortcutRecorder(combo: .default, model: FlixShortcutRecorderModel(), reset: {})
        FlixShortcutRecorder(combo: FlixShortcutCombo(keyCode: 49, modifiers: [.control, .command]),
                             model: FlixShortcutRecorderModel(), reset: {})
    }
    .padding(30)
}
#endif
