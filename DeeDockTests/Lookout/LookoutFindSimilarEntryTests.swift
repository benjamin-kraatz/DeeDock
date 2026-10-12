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
