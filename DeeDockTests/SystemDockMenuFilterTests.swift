import Testing
@testable import DeeDock

/// The menu shapes below are recorded from real applications on macOS 27.
struct SystemDockMenuFilterTests {
    private static let systemSection = ["Show All Windows", "Hide", "Hide Others", "Quit", "Force Quit"]

    private func entries(_ rows: [String?], submenus: Set<String> = ["Options"], checked: Set<String> = []) -> [SystemDockMenuEntry] {
        rows.enumerated().map { index, title in
            guard let title else { return .separator }
            let child = SystemDockMenuEntry(title: "Child", isEnabled: true, isChecked: false, path: [], children: [])
            return SystemDockMenuEntry(title: title, isEnabled: true, isChecked: checked.contains(title),
                                       path: [.init(index: index, title: title)],
                                       children: submenus.contains(title) ? [child] : [])
        }
    }

    private func titles(_ rows: [String?], windows: Set<String> = [], submenus: Set<String> = ["Options"]) -> [String] {
        SystemDockMenuFilter.applicationEntries(in: entries(rows, submenus: submenus), windowTitles: windows)
            .map(\.title)
    }

    @Test("Xcode keeps Open Developer Tool and loses recents, its window, and the Dock's sections")
    func recentsAndWindow() {
        let rows: [String?] = ["Topos.xcodeproj", "DeeDock.xcodeproj", nil, nil, "DeeDock — New Editor", nil,
                               "Open Developer Tool", nil, "Options", nil] + Self.systemSection
        #expect(titles(rows, windows: ["DeeDock — New Editor"], submenus: ["Open Developer Tool", "Options"]) == ["Open Developer Tool"])
    }

    @Test("One known title removes the window section, even when another Space hides the rest")
    func windowSection() {
        let rows: [String?] = ["…/dzwei/Topos", "Hidden Space", nil, "New Window", "New Tab", nil, "Options", nil] + Self.systemSection
        #expect(titles(rows, windows: ["…/dzwei/Topos"]) == ["New Window", "New Tab"])
    }

    @Test("A checked command in the first section stays with its neighbours")
    func checkedCommand() {
        let rows: [String?] = ["Shuffle", "Next Track", nil, "Options", nil] + Self.systemSection
        let filtered = SystemDockMenuFilter.applicationEntries(in: entries(rows, checked: ["Shuffle"]), windowTitles: [])
        #expect(filtered.map(\.title) == ["Shuffle", "Next Track"])
        #expect(filtered[0].isChecked)
    }

    @Test("Without a known title, the first section stays with the application's rows")
    func unmatchedFirstSection() {
        let rows: [String?] = ["New Window", nil, "Options", nil] + Self.systemSection
        #expect(titles(rows) == ["New Window"])
    }

    @Test("An app with only a window and the Dock's sections adds nothing")
    func nothingOfItsOwn() {
        let rows: [String?] = ["T3 Code", nil, "Options", nil] + Self.systemSection
        #expect(titles(rows, windows: ["T3 Code"]).isEmpty)
    }

    @Test("Several application sections keep their order and a separator between them")
    func applicationSections() {
        let rows: [String?] = ["Chat", nil, "Recent", "More", nil, "Other", nil, "Options", nil] + Self.systemSection
        let filtered = SystemDockMenuFilter.applicationEntries(in: entries(rows, submenus: ["More", "Options"]), windowTitles: ["Chat"])
        #expect(filtered.map(\.title) == ["Recent", "More", "", "Other"])
        #expect(filtered[1].children.count == 1)
    }

    @Test("Finder has no Options row, so its last section of rows is kept")
    func finder() {
        let rows: [String?] = ["New Window", "Find", nil, "Go to Folder", nil, "Documents", "Downloads", nil,
                               "Show All Windows", "Hide", "Hide Others"]
        #expect(titles(rows) == ["New Window", "Find", "", "Go to Folder", "", "Documents", "Downloads"])
    }

    @Test("A menu that is only the system section yields nothing")
    func systemSectionOnly() {
        #expect(titles(Self.systemSection).isEmpty)
        #expect(titles([]).isEmpty)
    }
}
