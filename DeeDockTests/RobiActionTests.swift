import Foundation
import FoundationModels
import Synchronization
import Testing
@testable import DeeDock

/// Robi proposes steps in the app: menu commands it browses page by page, and presses, toggles
/// and typing on the window's elements. These tests cover what can drift: the menu pages the
/// model reads, the checks that keep it from inventing targets, and the three-step limit.
@Suite("Robi actions")
struct RobiActionTests {
    private static let catalog = RobiMenuCatalog(menus: [
        .init(title: "File", paths: (1...30).map { "File > Item \($0)" }, isComplete: true),
        .init(title: "View", paths: ["View > Show Sidebar", "View > Zoom In"], isComplete: true),
        .init(title: "Window", paths: (1...25).map { "Window > Item \($0)" }, isComplete: false),
    ], isComplete: false)
    private static let paging = RobiMenuCatalog.Paging(firstPage: 3, pageSize: 10)

    // MARK: Menu catalog

    @Test("The overview counts each menu, shows its first commands, and says where the next page starts")
    func overview() {
        let text = Self.catalog.overview(Self.paging)
        #expect(text.contains("File (30 commands):\nFile > Item 1\nFile > Item 2\nFile > Item 3\n… 27 more in File, next cursor 3"))
        #expect(text.contains("View (2 commands):\nView > Show Sidebar\nView > Zoom In"))
        #expect(!text.contains("more in View"))
        // A menu the read stopped in is counted with a plus.
        #expect(text.contains("Window (25+ commands):"))
        #expect(text.hasSuffix("Some menus were too long to read in full."))
    }

    @Test("A page starts at its cursor and gives the next one until the menu ends")
    func pages() {
        let page = Self.catalog.page(menu: "file", cursor: 3, Self.paging)
        #expect(page.hasPrefix("File > Item 4\n"))
        #expect(page.hasSuffix("File > Item 13\n… 17 more, next cursor 13"))
        let last = Self.catalog.page(menu: "File", cursor: 25, Self.paging)
        #expect(last == (26...30).map { "File > Item \($0)" }.joined(separator: "\n"))
        #expect(Self.catalog.page(menu: "File", cursor: 30, Self.paging) == "No more commands in File.")
        #expect(Self.catalog.page(menu: "Window", cursor: 20, Self.paging).hasSuffix("That is all Robi could read of Window."))
    }

    @Test("An unknown menu lists the real ones instead")
    func unknownMenu() {
        #expect(Self.catalog.page(menu: "Edit", cursor: 0, Self.paging)
            == "There is no menu named Edit. The menus are: File, View, Window.")
    }

    @Test("A proposal may use any path read, including ones the model has not been shown yet")
    func allPaths() {
        #expect(Self.catalog.allPaths.contains("File > Item 30"))
        #expect(Self.catalog.allPaths.count == 57)
    }

    // MARK: Proposing steps

    @Test("Steps collect in order up to three, and a fourth is refused")
    func collectsUpToThree() {
        let published = Mutex<[RobiProposal]>([])
        let collector = RobiStepCollector { proposal in published.withLock { $0.append(proposal) } }
        _ = collector.add(.menu(path: "File > New Tab"))
        _ = collector.add(.press(element: 2, label: "Send"))
        _ = collector.add(.toggle(element: 5, label: "Unread only", on: true))
        let refused = collector.add(.menu(path: "View > Zoom In"))
        #expect(refused.contains("already 3 steps"))
        let proposals = published.withLock { $0 }
        #expect(proposals.count == 3)
        #expect(proposals.last?.steps == [
            .menu(path: "File > New Tab"), .press(element: 2, label: "Send"), .toggle(element: 5, label: "Unread only", on: true),
        ])
    }

    @Test("A menu path that was not read is refused and proposes nothing")
    func refusesUnknownPath() async throws {
        let published = Mutex(0)
        let collector = RobiStepCollector { _ in published.withLock { $0 += 1 } }
        let tool = RobiProposeMenuCommand(paths: Self.catalog.allPaths, collector: collector)
        let reply = try await tool.call(arguments: .init(path: "File > Delete Everything"))
        #expect(reply.hasPrefix("That path is not in the menu."))
        #expect(published.withLock { $0 } == 0)
    }

    @Test("Element tools accept only their own kinds, and selecting an option becomes a press")
    func checksElementKinds() async throws {
        let published = Mutex<[RobiProposal]>([])
        let collector = RobiStepCollector { proposal in published.withLock { $0.append(proposal) } }
        let landmarks: [Int: RobiLandmark] = [
            1: RobiLandmark(id: 1, kind: .heading, label: "Inbox", frame: .zero),
            2: RobiLandmark(id: 2, kind: .button, label: "Send", frame: .zero),
            3: RobiLandmark(id: 3, kind: .option, label: "Dark", frame: .zero),
            4: RobiLandmark(id: 4, kind: .field, label: "Search", frame: .zero),
        ]
        let press = RobiProposePress(landmarks: landmarks, collector: collector)
        let toggle = RobiProposeToggle(landmarks: landmarks, collector: collector)
        let type = RobiProposeType(landmarks: landmarks, collector: collector)
        #expect(try await press.call(arguments: .init(element: 1)).contains("not a button or link"))
        #expect(try await type.call(arguments: .init(element: 2, text: "hi")).contains("not a field"))
        #expect(try await toggle.call(arguments: .init(element: 3, on: false)).contains("cannot be turned off"))
        _ = try await toggle.call(arguments: .init(element: 3, on: true))
        _ = try await type.call(arguments: .init(element: 4, text: "meeting"))
        #expect(published.withLock { $0.last?.steps } == [
            .press(element: 3, label: "Dark"), .type(element: 4, label: "Search", text: "meeting"),
        ])
    }
}
