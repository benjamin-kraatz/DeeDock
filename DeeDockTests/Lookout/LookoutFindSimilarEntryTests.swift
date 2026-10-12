import AppKit
import Foundation
import Testing
@testable import DeeDock

/// Find Similar's ways in beyond search results: the Files browser, the Apps tab's file actions for a file dropped on
/// the DOKK tile, and the header field, whose text editing must never take a dragged file as its path.
@MainActor struct LookoutFindSimilarEntryTests {
    private let home = URL(filePath: "/Users/tester")
    private let photo = HubFileItem.lookout(path: "/Users/tester/Desktop/IMG_5012.HEIC", isFolder: false, size: nil,
                                            modified: nil)
    private let pdf = HubFileItem.lookout(path: "/Users/tester/Downloads/Invoice_October.pdf", isFolder: false,
                                          size: nil, modified: nil)
    private let folder = HubFileItem.lookout(path: "/Users/tester/Desktop/Holiday", isFolder: true, size: nil,
                                             modified: nil)

    private func model(status: LookoutStatus = .ready) -> HubFilesModel {
        let suite = "dokk.tests.lookout.similar.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defaults.removePersistentDomain(forName: suite)
        let model = HubFilesModel(defaults: defaults, dataSource: HubFilesMemoryDataSource(home: home))
        model.previewOverrides.lookoutStatus = status
        return model
    }

    // MARK: The browser

    @Test func findSimilarInTheBrowserSearchesWithThePictureAndHasNoWordsToGoBackTo() {
        let model = model()
        #expect(!model.isSearching)
        #expect(model.similarAvailability(for: photo) == .available(isPicture: true))
        model.findSimilar(photo)
        #expect(model.isPictureSearch && model.isSearching)
        #expect(model.pictureQuery?.analyticsSource == .browser)
        // Its stored vector when the index holds it, else the picture read like a dropped one.
        #expect(model.pictureQuery?.input == .indexed(path: photo.url.path, segmentID: nil, fallback: photo.url))
        #expect(model.pictureSession.wordsBefore.isEmpty)
        #expect(model.query.isEmpty)
    }

    @Test func theBrowserOffersFindSimilarByWhatLookoutReadsAndHolds() {
        let model = model()
        #expect(model.similarAvailability(for: folder) == .hidden)
        #expect(model.similarAvailability(for: pdf) == .available(isPicture: false))   // until the index answers
        model.similarIndexed[pdf.url.path] = false
        #expect(model.similarAvailability(for: pdf) == .notIndexed)
        model.findSimilar(pdf)
        #expect(!model.isPictureSearch)   // disabled: nothing to search with
        model.similarIndexed[pdf.url.path] = true
        model.findSimilar(pdf)
        #expect(model.pictureQuery?.input == .indexed(path: pdf.url.path, segmentID: nil, fallback: nil))
        // Hidden until Lookout can search, as in search results.
        #expect(self.model(status: .notSetUp).similarAvailability(for: photo) == .hidden)
        #expect(self.model(status: .waitingForModel).similarAvailability(for: photo) == .hidden)
        #expect(self.model(status: .paused(.lowPowerMode)).similarAvailability(for: photo) == .available(isPicture: true))
    }

    @Test func findSimilarOnAFileFromOutsideTheTabSearchesWithIt() async {
        let model = model()
        let url = photo.url
        model.findSimilar(fileAt: url, via: .hubTile)
        #expect(model.pictureQuery?.analyticsSource == .hubTile)
        #expect(model.pictureQuery?.input == .indexed(path: url.path, segmentID: nil, fallback: url))
        // A picture Lookout reads needs no index lookup; a document the (inert) index doesn't hold can't be searched
        // with, and nothing can while Lookout isn't set up.
        let picture = await model.canFindSimilar(fileAt: url)
        let document = await model.canFindSimilar(fileAt: pdf.url)
        let notSetUp = await self.model(status: .notSetUp).canFindSimilar(fileAt: url)
        let svg = await model.canFindSimilar(fileAt: URL(filePath: "/Users/tester/Desktop/logo.svg"))
        #expect(picture && !document && !notSetUp && !svg)
    }

    // MARK: The Apps tab's file actions

    private func adoption(_ urls: [URL]) -> LauncherFileAdoption {
        .owned(DocumentResourceAccess(urls, startAccess: { _ in false }, stopAccess: { _ in }), source: .drop)
    }

    /// What the file actions asked Lookout and ran.
    @MainActor private final class Calls {
        var asked: [URL] = []
        var ran: [URL] = []
    }

    /// Waits for the file actions' check with Lookout, which runs in a task of its own.
    private func settle(_ state: LauncherFileActionState, until done: () -> Bool) async {
        for _ in 0..<200 where !done() { await Task.yield() }
    }

    @Test func aDroppedFileLookoutCanSearchWithListsFindSimilarFirst() async throws {
        let folder = LookoutTestFolder()
        let file = try folder.write("IMG_1.png")
        let calls = Calls()
        let state = LauncherFileActionState()
        state.similar = LauncherFileSimilar(isAvailable: { calls.asked.append($0); return true },
                                            run: { calls.ran.append($0) })
        state.adopt(adoption([file]))
        await settle(state) { state.similarURL != nil }
        #expect(calls.asked.map(\.lastPathComponent) == ["IMG_1.png"])
        let first = try #require(state.actions.first)
        #expect(first.id == .findSimilar && first.symbol == "photo.badge.magnifyingglass")
        #expect(first.title == String(localized: .lookoutSimilarButton))
        state.kind = .application
        #expect(!state.actions.contains { $0.id == .findSimilar })
        state.kind = .all
        state.activate(first)
        #expect(calls.ran.map(\.lastPathComponent) == ["IMG_1.png"])
        #expect(state.status == .idle)   // not a file operation
    }

    @Test func findSimilarIsNotOfferedForSeveralFilesOrWhenLookoutCantSearch() async throws {
        let folder = LookoutTestFolder()
        // The file actions hold the files as the drop gave them, which may be another spelling of the same path.
        let one = try folder.write("IMG_1.png"), two = try folder.write("IMG_2.png")
        let calls = Calls()
        let state = LauncherFileActionState()
        state.similar = LauncherFileSimilar(isAvailable: { calls.asked.append($0); return false }, run: { _ in })
        state.adopt(adoption([one, two]))
        await settle(state) { false }
        #expect(calls.asked.isEmpty && state.similarURL == nil)
        state.adopt(adoption([one]))
        await settle(state) { calls.asked.count == 1 }
        await settle(state) { false }
        #expect(calls.asked.map(\.lastPathComponent) == ["IMG_1.png"] && state.similarURL == nil)
        #expect(!state.actions.contains { $0.id == .findSimilar })
    }

    // MARK: The header field

    /// The field editor takes text drags only, so a dragged file reaches the field's drop target (which searches with
    /// it or refuses it) instead of being inserted as its path.
    @Test func theHubsFieldEditorNeverTakesAFileDragAsText() throws {
        let panel = HubPanel(contentRect: NSRect(x: 0, y: 0, width: 300, height: 80), styleMask: [.titled],
                             backing: .buffered, defer: false)
        let field = NSTextField(frame: NSRect(x: 10, y: 10, width: 200, height: 24))
        panel.contentView?.addSubview(field)
        #expect(panel.makeFirstResponder(field))
        let editor = try #require(panel.firstResponder as? NSTextView)
        #expect(editor.isFieldEditor)
        let types = Set(editor.registeredDraggedTypes)
        #expect(types == Set(HubPanel.fieldEditorDragTypes))
        #expect(!types.contains(.fileURL) && !types.contains(.URL) && !types.contains(.tiff) && !types.contains(.png))
        #expect(!types.contains(NSPasteboard.PasteboardType("NSFilenamesPboardType")))
        // Editing again (the field editor is reused) narrows it again.
        #expect(panel.makeFirstResponder(nil))
        #expect(panel.makeFirstResponder(field))
        #expect(Set((panel.firstResponder as? NSTextView)?.registeredDraggedTypes ?? []) == types)
        panel.close()
    }
}
