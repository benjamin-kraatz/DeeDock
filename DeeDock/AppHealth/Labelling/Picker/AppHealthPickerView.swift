import SwiftUI

/// The manual picker's content: the list of watched apps, or the picked app's label choices, on the same surface
/// as the prompt. The card hangs from the top of its window, so a height change unfolds downward.
struct AppHealthPickerView: View {
    static let width: CGFloat = 340

    let model: AppHealthPickerModel
    var overrides: AppHealthAccessibilityOverrides?
    let sizeChanged: (CGSize) -> Void
    @Environment(\.accessibilityReduceMotion) private var environmentReduceMotion
    @Environment(\.accessibilityReduceTransparency) private var environmentReduceTransparency

    init(model: AppHealthPickerModel, overrides: AppHealthAccessibilityOverrides? = nil,
         sizeChanged: @escaping (CGSize) -> Void = { _ in }) {
        self.model = model
        self.overrides = overrides
        self.sizeChanged = sizeChanged
    }

    var body: some View {
        Group {
            if let question = model.question {
                AppHealthQuestionContent(session: question, reduceMotion: reduceMotion, perform: nil)
            } else {
                AppHealthPickerList(model: model, reduceMotion: reduceMotion)
            }
        }
        .transition(reduceMotion ? .opacity : AnyTransition(.blurReplace))
        .animation(reduceMotion ? .easeInOut(duration: 0.12) : .smooth(duration: 0.3), value: model.question == nil)
        .padding(16)
        .frame(width: Self.width, alignment: .leading)
        .fixedSize(horizontal: false, vertical: true)
        .appHealthSurface(opaque: reduceTransparency)
        .onGeometryChange(for: CGSize.self) { $0.size } action: { sizeChanged($0) }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .tint(SettingsPage.appHealth.tint)
    }

    private var reduceMotion: Bool { overrides?.reduceMotion ?? environmentReduceMotion }
    private var reduceTransparency: Bool { overrides?.reduceTransparency ?? environmentReduceTransparency }
}

/// Title, filter field, the busiest apps, and "Show all".
struct AppHealthPickerList: View {
    /// Above this many rows the list scrolls.
    static let scrollThreshold = AppHealthPickerModel.topCount
    static let rowHeight: CGFloat = 36

    let model: AppHealthPickerModel
    var reduceMotion = false

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .top) {
                Text(.appHealthPickerTitle)
                    .font(.headline)
                    .accessibilityAddTraits(.isHeader)
                Spacer()
                AppHealthPromptCloseButton(reduceMotion: reduceMotion) { model.close?() }
                    .padding(.top, -2)
            }
            AppHealthPickerFilterField(model: model)
            rows
            if model.hiddenCount > 0 {
                Button(.appHealthPickerShowAll(count: model.entries.count)) { model.showAll() }
                    .buttonStyle(.borderless)
                    .font(.subheadline)
                    .foregroundStyle(.tint)
                    .transition(.opacity)
            }
        }
        .animation(reduceMotion ? .easeInOut(duration: 0.12) : .smooth(duration: 0.25),
                   value: model.visibleEntries.map(\.id))
    }

    @ViewBuilder private var rows: some View {
        let visible = model.visibleEntries
        if model.entries.isEmpty {
            AppHealthPickerMessage(text: .appHealthPickerEmpty)
        } else if visible.isEmpty {
            AppHealthPickerMessage(text: .appHealthPickerNoMatch)
        } else if visible.count > Self.scrollThreshold {
            ScrollViewReader { proxy in
                ScrollView {
                    rowStack(visible)
                }
                .frame(height: Self.rowHeight * CGFloat(Self.scrollThreshold))
                .onChange(of: model.highlightedID) { _, id in
                    if let id { proxy.scrollTo(id) }
                }
            }
        } else {
            rowStack(visible)
        }
    }

    private func rowStack(_ entries: [AppHealthPickerEntry]) -> some View {
        VStack(spacing: 0) {
            ForEach(entries) { entry in
                AppHealthPickerRow(entry: entry, isHighlighted: model.highlightedID == entry.id) {
                    model.choose(entry)
                }
                .frame(height: Self.rowHeight)
                .id(entry.id)
            }
        }
    }
}

/// The type-to-filter field. Takes focus whenever the model asks, which the panel does once it is key.
struct AppHealthPickerFilterField: View {
    @Bindable var model: AppHealthPickerModel
    @FocusState private var focused: Bool

    var body: some View {
        TextField(text: $model.query) {
            Text(.appHealthPickerFilter)
        }
        .textFieldStyle(.roundedBorder)
        .focused($focused)
        .onChange(of: model.focusRequest, initial: true) { focused = true }
    }
}

/// One watched app: icon and name from macOS, CPU and memory from the latest tick. The keyboard highlight is a
/// tinted band; the pointer gets a quieter one.
struct AppHealthPickerRow: View {
    let entry: AppHealthPickerEntry
    let isHighlighted: Bool
    let pick: () -> Void
    @State private var hovering = false

    var body: some View {
        Button(action: pick) {
            HStack(spacing: 10) {
                AppHealthAppIcon(icon: entry.display.icon, size: 24)
                Text(verbatim: entry.display.name)
                    .lineLimit(1)
                    .truncationMode(.tail)
                Spacer(minLength: 8)
                Text(verbatim: usage)
                    .font(.callout.monospacedDigit())
                    .foregroundStyle(.secondary)
            }
            .padding(.horizontal, 8)
            .frame(maxHeight: .infinity)
            .contentShape(.rect)
            .background {
                RoundedRectangle(cornerRadius: 7, style: .continuous)
                    .fill(isHighlighted ? AnyShapeStyle(.tint.opacity(0.18))
                          : hovering ? AnyShapeStyle(.primary.opacity(0.06)) : AnyShapeStyle(.clear))
            }
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
        .animation(.easeOut(duration: 0.12), value: hovering)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text(verbatim: entry.display.name))
        .accessibilityValue(Text(.appHealthPickerRowValue(cpu: cpu, memory: memory)))
        .accessibilityHint(Text(.appHealthPickerRowHint))
        .accessibilityAddTraits(isHighlighted ? [.isButton, .isSelected] : .isButton)
    }

    private var cpu: String { AppHealthReasonText.percent(entry.sample.cpuPercent) }
    private var memory: String { ByteCountFormatter.string(fromByteCount: Int64(entry.sample.mem), countStyle: .memory) }
    private var usage: String { String(localized: .appHealthPickerRowValue(cpu: cpu, memory: memory)) }
}

/// A one-line note in place of the list.
struct AppHealthPickerMessage: View {
    let text: LocalizedStringResource

    var body: some View {
        Text(text)
            .font(.subheadline)
            .foregroundStyle(.secondary)
            .fixedSize(horizontal: false, vertical: true)
            .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
    }
}

#if DEBUG
#Preview("Picker") {
    AppHealthPickerView(model: AppHealthPickerModel(entries: AppHealthLabellingPreviewData.pickerEntries))
        .padding()
}

#Preview("Picker, no data yet, dark") {
    AppHealthPickerView(model: AppHealthPickerModel(entries: []))
        .padding()
        .preferredColorScheme(.dark)
}

#Preview("Picker, picked app") {
    let model = AppHealthPickerModel(entries: AppHealthLabellingPreviewData.pickerEntries)
    model.question = AppHealthLabellingPreviewData.session(reason: nil, source: .manual)
    return AppHealthPickerView(model: model)
        .padding()
}

#Preview("Picker, Reduce Motion and Transparency, German") {
    AppHealthPickerView(model: AppHealthPickerModel(entries: AppHealthLabellingPreviewData.pickerEntries),
                        overrides: AppHealthAccessibilityOverrides(reduceMotion: true, reduceTransparency: true))
        .padding()
        .environment(\.locale, Locale(identifier: "de"))
}
#endif
