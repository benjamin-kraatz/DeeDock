import AppKit
import ImageIO
import UniformTypeIdentifiers

/// Searching with a picture in the Files tab (`docs/mockups/lookout-image-search.html`): the search field's chip and
/// drop well, pasting a picture, Find Similar, the picture results' selection and folds, and opening their hits.
///
/// A picture replaces the words in the field (`LookoutPictureSession`); while it's there `isSearching` is true, the
/// names section is gone, and `lookoutSelection` walks the picture results' groups instead of the text results.
extension HubFilesModel {
    // MARK: State

    var pictureQuery: LookoutPictureQuery? { pictureSession.picture }
    var isPictureSearch: Bool { pictureSession.isActive }
    var picturePhase: LookoutPictureSearch.Phase { previewOverrides.picturePhase ?? lookout.pictureSearch.phase }
    var pictureResults: LookoutSimilarResults { previewOverrides.pictureResults ?? lookout.pictureSearch.results }
    var pictureReadSeconds: Double? { previewOverrides.pictureReadSeconds ?? lookout.pictureSearch.readSeconds }

    /// What the picture results show under the results bar.
    var pictureContent: LookoutPictureContent {
        LookoutPictureContent(status: lookoutDisplayStatus, phase: picturePhase, results: pictureResults)
    }

    /// The results bar's line under the picture's name.
    var pictureSubtitle: LookoutPictureSubtitle {
        LookoutPictureSubtitle(isPasted: pictureQuery?.fileURL == nil, phase: picturePhase,
                               canSearch: LookoutPictureContent.canSearch(lookoutDisplayStatus),
                               stored: previewOverrides.pictureResults == nil ? lookout.pictureSearch.storedSource
                                   : previewOverrides.pictureStoredSource,
                               readSeconds: pictureReadSeconds)
    }

    /// Whether Lookout can search with a picture now: set up, and ready, reading files, or paused. Find Similar is
    /// hidden otherwise, as in the mockup.
    var canSearchPictures: Bool {
        switch lookoutStatus {
        case .ready, .indexing, .paused: true
        case .notSetUp, .off, .waitingForModel, .failed: false
        }
    }

    /// The picture results' hits as listed: each group's strong hits, then its weaker ones while its fold is open.
    var visiblePictureHits: [LookoutHit] {
        pictureResults.groups.flatMap { pictureWeakExpanded.contains($0.kind) ? $0.all : $0.strong }
    }

    // MARK: Starting and ending

    /// Starts searching with `picture`: it replaces the words in the field (which come back with ⌫), the results
    /// show its two groups, and the field takes focus.
    func searchWithPicture(_ picture: LookoutPictureQuery) {
        let wasSearching = isSearching
        // The search by words ends here, whatever it showed.
        if !isPictureSearch { endLookoutSearchSession() }
        pictureSession.begin(picture, replacingWords: query)
        pictureWeakExpanded = []
        searchedPictureID = nil
        if !query.isEmpty { setQueryForPicture("") }
        searchDidChange(wasSearching: wasSearching)
        shell?.focusSearchField()
    }

    /// Removes the picture.
    ///
    /// - Parameter restoringWords: Give the words from before the picture back (⌫, ✕, "Back to …"), or leave the
    ///   field empty (the clear button, Escape).
    func removePicture(restoringWords: Bool) {
        guard isPictureSearch else { return }
        let wasSearching = isSearching
        let words = pictureSession.remove(restoringWords: restoringWords)
        lookout.pictureSearch.clear()
        searchedPictureID = nil
        pictureWeakExpanded = []
        if query != words { setQueryForPicture(words) }
        searchDidChange(wasSearching: wasSearching)
    }

    /// Typing replaced the picture: forget it and its search (called while `query` changes).
    func endPictureSearch() {
        pictureSession.typed()
        lookout.pictureSearch.clear()
        searchedPictureID = nil
        pictureWeakExpanded = []
    }

    /// Runs the picture search, or reuses its vector for a scope change or when the tab appears again.
    func runPictureSearch(_ picture: LookoutPictureQuery) {
        if searchedPictureID == picture.id, lookout.pictureSearch.rescope(resolvedSearchScope) { return }
        searchedPictureID = picture.id
        lookout.pictureSearch.search(picture.input, source: picture.analyticsSource, scope: resolvedSearchScope)
    }

    private func setQueryForPicture(_ text: String) {
        settingQueryForPicture = true
        query = text
        settingQueryForPicture = false
    }

    // MARK: Find Similar

    /// Whether Find Similar is offered for `item`, a name result or a Lookout hit.
    func similarAvailability(for item: HubFileItem) -> LookoutSimilarAvailability {
        let inIndex = isLookoutHitPath(item.url.path) ? true : similarIndexed[item.url.path]
        return LookoutSimilarAvailability.of(item.url, isDirectory: item.isDirectory, canSearch: canSearchPictures,
                                             inIndex: inIndex, options: similarOptions)
    }

    /// Learns whether the index holds `item`, so a document outside it shows no Find Similar. Cheap: one indexed
    /// query; the answer is kept for the session.
    func checkSimilarIndexed(_ item: HubFileItem) async {
        let path = item.url.path
        guard canSearchPictures, !item.isDirectory, similarIndexed[path] == nil, !isLookoutHitPath(path),
              previewOverrides.lookoutStatus == nil else { return }
        let found = await lookout.indexedPaths([path])
        similarIndexed[path] = found.contains(path)
    }

    /// Find Similar on a result: a Lookout hit searches with the segment it matched (that PDF page), anything else
    /// with the file's picture or first segment; a picture the index doesn't hold is read like a dropped one.
    func findSimilar(_ item: HubFileItem, segmentID: Int64? = nil) {
        guard case .available(let isPicture) = similarAvailability(for: item) else { return }
        searchWithPicture(.similar(item.url, segmentID: segmentID, isPicture: isPicture))
    }

    /// ⌘⇧L, the menu item and the button: Find Similar on the one selected search result.
    func findSimilarForSelection() {
        guard isSearching else { return }
        if let hit = selectedLookoutHit {
            findSimilar(hit.fileItem, segmentID: hit.segmentID)
        } else if actionableItems.count == 1, let item = actionableItems.first {
            findSimilar(item)
        }
    }

    /// Whether the single selected search result has Find Similar to offer, for the button and the menu.
    var selectionSimilarAvailability: LookoutSimilarAvailability {
        guard isSearching, actionableItems.count == 1, let item = actionableItems.first else { return .hidden }
        return similarAvailability(for: item)
    }

    private var similarOptions: IndexOptions {
        var options = IndexOptions()
        options.excludedExtensions = IndexOptions.extensions(lookout.settings.excludedExtensions.joined(separator: ","))
        return options
    }

    private func isLookoutHitPath(_ path: String) -> Bool {
        let hits = isPictureSearch ? pictureResults.all : lookoutResults.all
        return hits.contains { $0.path == path && !$0.isFolder }
    }

    // MARK: Paste

    /// ⌘V with a picture on the pasteboard and no text: searches with it. A picture file copied in Finder counts
    /// too. Anything else is left to the field.
    ///
    /// - Returns: Whether a picture was pasted.
    func pastePicture(from pasteboard: NSPasteboard = .general) -> Bool {
        guard isVisible, lookoutStatus != .off else { return false }
        let files = pasteboard.readObjects(forClasses: [NSURL.self], options: [.urlReadingFileURLsOnly: true])
            as? [URL] ?? []
        if let file = files.first {
            guard files.count == 1, LookoutPictureDrop.isPictureFile(file) else { return false }
            searchWithPicture(.dropped(file, via: .paste))
            return true
        }
        guard pasteboard.string(forType: .string) == nil, let data = Self.pictureData(on: pasteboard) else {
            return false
        }
        searchWithPicture(.pasted(data, image: Self.thumbnail(of: data)))
        return true
    }

    /// The pasteboard types picture bytes come as, best first.
    static let pictureTypes: [NSPasteboard.PasteboardType] = [
        .png, .tiff, NSPasteboard.PasteboardType(UTType.jpeg.identifier), NSPasteboard.PasteboardType(UTType.heic.identifier),
    ]

    static func pictureData(on pasteboard: NSPasteboard) -> Data? {
        guard let type = pasteboard.availableType(from: pictureTypes) else { return nil }
        return pasteboard.data(forType: type)
    }

    /// A 128 px picture of pasted bytes for the chip and the results bar, decoded straight to that size.
    static func thumbnail(of data: Data) -> NSImage? {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil) else { return nil }
        let options: [CFString: Any] = [kCGImageSourceCreateThumbnailFromImageAlways: true,
                                        kCGImageSourceThumbnailMaxPixelSize: 128,
                                        kCGImageSourceCreateThumbnailWithTransform: true]
        guard let image = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary) else { return nil }
        return NSImage(cgImage: image, size: NSSize(width: image.width, height: image.height))
    }

    // MARK: Selection and folds

    /// Opens or closes a group's "Weaker matches". Closing it while one of its weaker hits is selected moves the
    /// selection to the group's last strong hit.
    func setPictureWeakExpanded(_ group: LookoutSimilarResults.GroupKind, _ expanded: Bool) {
        guard expanded != pictureWeakExpanded.contains(group) else { return }
        if expanded {
            pictureWeakExpanded.insert(group)
            Analytics.count(.lookoutWeakMatchesExpanded)
        } else {
            pictureWeakExpanded.remove(group)
            guard let path = lookoutSelection,
                  let shown = pictureResults.groups.first(where: { $0.kind == group }),
                  shown.weak.contains(where: { $0.path == path }) else { return }
            lookoutSelection = shown.strong.last?.path
            quickLook.selectionDidChange()
        }
    }

    /// The group the selected hit is in, for → and ←.
    var selectedPictureGroup: LookoutSimilarResults.Group? {
        lookoutSelection.flatMap { pictureResults.group(containing: $0) }
    }

    // MARK: Open

    /// `lookout_result_opened` for a hit of a search with a picture: strong or weak, and its rank within its group.
    func trackPictureResultOpened(_ hit: LookoutHit) {
        for group in pictureResults.groups {
            if let index = group.strong.firstIndex(where: { $0.path == hit.path }) {
                Analytics.track(LookoutAnalytics.opened(hit, section: .strong, rank: index + 1,
                                                        scope: analyticsSearchScope, isLookup: false, query: .image))
                return
            }
            if let index = group.weak.firstIndex(where: { $0.path == hit.path }) {
                Analytics.track(LookoutAnalytics.opened(hit, section: .weak, rank: index + 1,
                                                        scope: analyticsSearchScope, isLookup: false, query: .image))
                return
            }
        }
    }
}

// MARK: - The search field

extension HubFilesModel: HubSearchExtras {
    var searchExtras: (any HubSearchExtras)? { self }

    var searchToken: HubSearchToken? {
        guard let picture = pictureQuery else { return nil }
        return HubSearchToken(id: picture.id, title: picture.name, fileURL: picture.fileURL, image: picture.image,
                              accessibilityLabel: String(localized: .lookoutPictureTokenLabel(picture.name)))
    }

    var searchTokenPrompt: LocalizedStringResource { .lookoutPicturePrompt }
    var searchDropState: HubSearchDropState { pictureDropState }
    var isSearchDropTargeted: Bool { isPictureDropTargeted }
    var searchDropTypes: [UTType] { [.fileURL, .image] }

    func removeSearchToken() { removePicture(restoringWords: true) }
    func clearSearchWithToken() { removePicture(restoringWords: false) }

    func hubDragChanged(inside: Bool) { pictureDragActivity("hub", inside: inside) }

    func searchFieldDragTargeted(_ targeted: Bool) {
        pictureDragActivity("field", inside: targeted)
        isPictureDropTargeted = targeted && searchFieldAcceptsDrag
    }

    var searchFieldAcceptsDrag: Bool { pictureDrag.drop?.isAccepted == true }

    func searchFieldPerformDrop() -> Bool {
        let pasteboard = NSPasteboard(name: .drag)
        let drop = pictureDrag.drop
        pictureDragEnded()
        switch drop {
        case .picture(let url):
            searchWithPicture(.dropped(url))
        case .similar(let url):
            if let hit = (isPictureSearch ? pictureResults.all : lookoutResults.all).first(where: { $0.path == url.path }) {
                findSimilar(hit.fileItem, segmentID: hit.segmentID)
            } else if let item = searchResults.first(where: { $0.url == url }) {
                findSimilar(item)
            } else {
                return false
            }
        case .imageData:
            guard let data = Self.pictureData(on: pasteboard) else { return false }
            searchWithPicture(.pasted(data, image: Self.thumbnail(of: data), via: .drop))
        case .refused, nil:
            return false
        }
        return true
    }

    // MARK: Drag tracking

    /// A drag began in one of the Files tab's own regions (a pane or a search result).
    func pictureDragBegan(fromSearchResult: Bool) {
        pictureDrag.began(fromSearchResult ? .searchResult : .filesPane)
    }

    /// A region with key `key` heard a drag enter or leave. The first entry classifies the drag and opens the well;
    /// a picture also wakes Lookout's picture reader, so it's ready by the drop.
    func pictureDragActivity(_ key: String, inside: Bool) {
        guard isVisible, lookoutStatus != .off else { return }
        if inside {
            guard pictureDrag.enter(key) else { return }
            let drop = pictureDrag.classify(NSPasteboard(name: .drag)) { classifyDrag($0) }
            switch drop {
            case .refused?:
                pictureDropState = .refusing(message: String(localized: .lookoutPictureDropRefused))
            case .some(.picture), .some(.imageData):
                pictureDropState = .accepting(message: String(localized: .lookoutPictureDropHere))
                // A picture from outside is most likely headed for the field. Pictures moved between the tab's own
                // panes usually aren't, and the reader's 555 MB shouldn't load for every move.
                if pictureDrag.origin == .outside { lookout.warmPictureReader() }
            case .some(.similar):
                pictureDropState = .accepting(message: String(localized: .lookoutPictureDropHere))
            case nil:
                pictureDropState = .none
            }
        } else {
            pictureDrag.exit(key) { [weak self] in self?.closeDropWell() }
        }
    }

    /// The drag ended (dropped anywhere, or cancelled): the well closes at once.
    func pictureDragEnded() {
        pictureDrag.sessionEnded()
        closeDropWell()
    }

    private func closeDropWell() {
        pictureDrag.reset()
        pictureDropState = .none
        isPictureDropTargeted = false
    }

    private func classifyDrag(_ pasteboard: NSPasteboard) -> LookoutPictureDrop? {
        // DOKK's own dock-item drags rearrange the dock; the field has nothing to say about them.
        guard pasteboard.string(forType: DockDragCoordinator.pasteboardType) == nil else { return nil }
        let urls = pasteboard.readObjects(forClasses: [NSURL.self], options: [.urlReadingFileURLsOnly: true])
            as? [URL] ?? []
        let hasImageData = pasteboard.availableType(from: Self.pictureTypes) != nil
        let hits = isPictureSearch ? pictureResults.all : lookoutResults.all
        let names = isPictureSearch ? [] : searchResults
        let fromResults = pictureDrag.origin == .searchResult
        return LookoutPictureDrop.classify(urls: urls, hasImageData: hasImageData,
                                           fromFilesPane: pictureDrag.origin == .filesPane) { url in
            // A Lookout hit is in the index, so Find Similar works on it; a folder hit has nothing to search with.
            if let hit = hits.first(where: { $0.path == url.path }) {
                return hit.isFolder ? .hidden : .available(isPicture: LookoutPictureDrop.isPictureFile(url))
            }
            // A name result dragged out of the results: Find Similar, when Lookout can.
            if fromResults, let item = names.first(where: { $0.url == url }) { return similarAvailability(for: item) }
            return nil
        }
    }
}
