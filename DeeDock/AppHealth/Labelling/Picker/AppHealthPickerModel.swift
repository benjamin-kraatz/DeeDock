import Foundation
import Observation

/// The state of the "Something's off right now…" picker: the watched apps, the filter, the keyboard highlight,
/// and, once an app is picked, its labelling question.
@MainActor @Observable
final class AppHealthPickerModel {
    /// How many apps show before "Show all".
    static let topCount = 10

    /// Every watched app of the latest tick, busiest first.
    let entries: [AppHealthPickerEntry]
    /// Type-to-filter text, matched against app names and bundle identifiers.
    var query = "" {
        didSet { highlightedID = visibleEntries.first?.id }
    }
    private(set) var showsAll = false
    private(set) var highlightedID: String?
    /// The picked app's question; nil while the list shows.
    var question: AppHealthLabelSession?
    /// Bumped to ask the filter field to take focus, once the panel is key.
    private(set) var focusRequest = 0

    /// The person picked an app.
    @ObservationIgnored var pick: ((AppHealthPickerEntry) -> Void)?
    /// The person closed the picker.
    @ObservationIgnored var close: (() -> Void)?

    init(entries: [AppHealthPickerEntry]) {
        self.entries = entries
        highlightedID = entries.first?.id
    }

    /// The rows on screen: every match while filtering, else the busiest ten until "Show all".
    var visibleEntries: [AppHealthPickerEntry] {
        let query = query.trimmingCharacters(in: .whitespaces)
        if !query.isEmpty {
            return entries.filter {
                $0.display.name.localizedStandardContains(query) || $0.sample.app.localizedStandardContains(query)
            }
        }
        return showsAll ? entries : Array(entries.prefix(Self.topCount))
    }

    /// Apps hidden behind "Show all".
    var hiddenCount: Int {
        query.trimmingCharacters(in: .whitespaces).isEmpty && !showsAll ? max(0, entries.count - Self.topCount) : 0
    }

    func showAll() {
        showsAll = true
    }

    func moveHighlight(by offset: Int) {
        let visible = visibleEntries
        guard !visible.isEmpty else { return }
        let current = highlightedID.flatMap { id in visible.firstIndex { $0.id == id } } ?? (offset > 0 ? -1 : 0)
        highlightedID = visible[min(max(current + offset, 0), visible.count - 1)].id
    }

    func pickHighlighted() {
        guard let entry = visibleEntries.first(where: { $0.id == highlightedID }) ?? visibleEntries.first else { return }
        pick?(entry)
    }

    func choose(_ entry: AppHealthPickerEntry) {
        highlightedID = entry.id
        pick?(entry)
    }

    func requestFocus() {
        focusRequest &+= 1
    }
}
