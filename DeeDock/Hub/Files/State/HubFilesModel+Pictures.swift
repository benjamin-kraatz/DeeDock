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
        lookout.pictureSearch.search(picture.input, source: picture.analyticsSource, scope: resolvedSearchScope,
                                     id: picture.id)
    }

    private func setQueryForPicture(_ text: String) {
        settingQueryForPicture = true
        query = text
        settingQueryForPicture = false
    }

    // MARK: Find Similar

    /// Whether Find Similar is offered for `item`: a name result, a Lookout hit, or a file in the browser.
    func similarAvailability(for item: HubFileItem) -> LookoutSimilarAvailability {
        let inIndex = isLookoutHitPath(item.url.path) ? true : similarIndexed[item.url.path]
        return LookoutSimilarAvailability.of(item.url, isDirectory: item.isDirectory, canSearch: canSearchPictures,
                                             inIndex: inIndex, options: similarOptions)
    }

    /// Learns whether the index holds `item`, a document, so one Lookout hasn't read shows Find Similar disabled with
    /// why. Cheap: one indexed query. A file the index holds is remembered for the session; one it doesn't is asked
    /// about again when it's selected again, since the backfill may have read it meanwhile.
    func checkSimilarIndexed(_ item: HubFileItem) async {
        let path = item.url.path
        guard canSearchPictures, similarIndexed[path] != true, !isLookoutHitPath(path),
              previewOverrides.lookoutStatus == nil,
              LookoutSimilarAvailability.dependsOnIndex(item.url, isDirectory: item.isDirectory, options: similarOptions)
        else { return }
        similarIndexed[path] = await isIndexed(path)
    }

    /// Find Similar on a result or a file in the browser: a Lookout hit searches with the segment it matched (that PDF
    /// page), anything else with the file's picture or first segment; a picture the index doesn't hold is read like a
    /// dropped one. From the browser there were no words, so the results bar has no "Back to".
    func findSimilar(_ item: HubFileItem, segmentID: Int64? = nil) {
        guard case .available(let isPicture) = similarAvailability(for: item) else { return }
        let source: AnalyticsLookoutImageSource = isSearching ? .similar : .browser
        searchWithPicture(.similar(item.url, segmentID: segmentID, isPicture: isPicture, via: source))
    }

    /// ⌘⇧L, the menu item and the button: Find Similar on the one selected search result or browser file.
    func findSimilarForSelection() {
        if isSearching, let hit = selectedLookoutHit {
            findSimilar(hit.fileItem, segmentID: hit.segmentID)
        } else if actionableItems.count == 1, let item = actionableItems.first {
            findSimilar(item)
        }
    }

    /// Whether the single selected item (a search result, or a file in the active pane) has Find Similar to offer,
    /// for the button, the menu and ⌘⇧L.
    var selectionSimilarAvailability: LookoutSimilarAvailability {
        guard actionableItems.count == 1, let item = actionableItems.first else { return .hidden }
        return similarAvailability(for: item)
    }

    /// Whether Find Similar can search with the file at `url`, which came from outside the tab (a file dropped on the
    /// DOKK tile, offered in the Apps tab's file actions): Lookout can search, and it's a picture Lookout reads or a
    /// file the index holds. Asks the index for a document.
    func canFindSimilar(fileAt url: URL) async -> Bool {
        let values = try? url.resourceValues(forKeys: [.isDirectoryKey, .isPackageKey])
        let isDirectory = values.map { $0.isDirectory == true && $0.isPackage != true } ?? url.hasDirectoryPath
        var inIndex: Bool?
        if LookoutSimilarAvailability.dependsOnIndex(url, isDirectory: isDirectory, options: similarOptions) {
            inIndex = await isIndexed(url.path)
        }
        return LookoutSimilarAvailability.of(url, isDirectory: isDirectory, canSearch: canSearchPictures,
                                             inIndex: inIndex, options: similarOptions).isAvailable
    }

    /// Find Similar on the file at `url` from outside the tab (`canFindSimilar(fileAt:)` said it can): its stored
    /// vector when the index holds it, else, for a picture, the picture read like a dropped one.
    func findSimilar(fileAt url: URL, via source: AnalyticsLookoutImageSource) {
        searchWithPicture(.similar(url, segmentID: nil, isPicture: LookoutPictureDrop.isPictureFile(url), via: source))
    }

    /// Whether the index holds a vector for the file at `path`.
    private func isIndexed(_ path: String) async -> Bool {
        await lookout.indexedPaths([path]).contains(path)
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

    /// The search field's key in the drag tracking (`HubFilesPictureDrag`).
    static let fieldDragKey = "field"

    func searchFieldDragTargeted(_ targeted: Bool) {
        pictureDragActivity(Self.fieldDragKey, inside: targeted)
        isPictureDropTargeted = targeted && searchFieldAcceptsDrag
    }

    var searchFieldAcceptsDrag: Bool { pictureDrag.drop?.isAccepted == true }

    func searchFieldPerformDrop() -> Bool {
        let pasteboard = NSPasteboard(name: .drag)
        let drop = pictureDrag.drop
        let origin = pictureDrag.origin
        pictureDragEnded()
        switch drop {
        case .picture(let url):
            // Its stored vector when the index holds it, else the picture read.
            searchWithPicture(.dropped(url))
        case .similar(let url):
            if let hit = (isPictureSearch ? pictureResults.all : lookoutResults.all).first(where: { $0.path == url.path }) {
                findSimilar(hit.fileItem, segmentID: hit.segmentID)
            } else if origin == .searchResult, let item = searchResults.first(where: { $0.url == url }) {
                findSimilar(item)
            } else {
                // A document the index holds, from a pane or from outside DOKK: its stored vector.
                searchWithPicture(.dropped(url))
            }
        case .imageData:
            guard let data = Self.pictureData(on: pasteboard) else { return false }
            searchWithPicture(.pasted(data, image: Self.thumbnail(of: data), via: .drop))
        case .unread, .refused, nil:
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
    /// a picture from outside DOKK also wakes Lookout's picture reader, so it's ready by the drop.
    func pictureDragActivity(_ key: String, inside: Bool) {
        guard isVisible, lookoutStatus != .off else { return }
        if inside {
            guard pictureDrag.enter(key) else { return }
            let pasteboard = NSPasteboard(name: .drag)
            forgetUnreadAnswer(for: Self.draggedFiles(on: pasteboard).first)
            showDropWell(for: pictureDrag.classify(pasteboard) { classifyDrag($0) })
        } else {
            pictureDrag.exit(key) { [weak self] in self?.closeDropWell() }
        }
    }

    private func showDropWell(for drop: LookoutPictureDrop?) {
        switch drop {
        case .refused?:
            pictureDropState = .refusing(message: String(localized: .lookoutPictureDropRefused))
        case .unread?:
            pictureDropState = .refusing(message: String(localized: .lookoutSimilarNotIndexed))
        case .some(.picture), .some(.imageData):
            pictureDropState = .accepting(message: String(localized: .lookoutPictureDropHere))
            // A picture from outside is most likely headed for the field. Pictures moved between the tab's own
            // panes usually aren't, and the reader's 555 MB shouldn't load for every move. Documents never wake it.
            if pictureDrag.origin == .outside { lookout.warmPictureReader() }
        case .similar(let url)?:
            let message: LocalizedStringResource = LookoutPictureDrop.isPictureFile(url) ? .lookoutPictureDropHere
                : .lookoutPictureDropDocument
            pictureDropState = .accepting(message: String(localized: message))
        case nil:
            pictureDropState = .none
            lookUpDraggedDocument()
        }
    }

    /// A new drag over the Hub asks the index again about a document it didn't hold last time: the backfill may have
    /// read it since. A file the index holds stays known for the session.
    func forgetUnreadAnswer(for url: URL?) {
        guard let path = url?.path, similarIndexed[path] == false else { return }
        similarIndexed[path] = nil
    }

    /// A dragged document whose place in the index isn't known yet: asks the index (one query, a few milliseconds)
    /// and classifies the drag again with the answer, while it's still the same drag over the Hub. The answer is
    /// kept for that drag; one the index didn't hold is asked again on the next (`forgetUnreadAnswer`). The lookup is `dragLookup`, cancelled when the well closes.
    private func lookUpDraggedDocument() {
        let pasteboard = NSPasteboard(name: .drag)
        guard canSearchPictures, let url = Self.draggedFiles(on: pasteboard).first, similarIndexed[url.path] == nil,
              LookoutSimilarAvailability.dependsOnIndex(url, isDirectory: url.hasDirectoryPath, options: similarOptions)
        else { return }
        let changeCount = pasteboard.changeCount
        dragLookup?.cancel()
        dragLookup = Task { [weak self] in
            guard let self else { return }
            let held = await isIndexed(url.path)
            guard !Task.isCancelled else { return }
            dragLookup = nil
            similarIndexed[url.path] = held
            let current = NSPasteboard(name: .drag)
            guard pictureDrag.isActive, current.changeCount == changeCount else { return }
            pictureDrag.forgetClassification()
            showDropWell(for: pictureDrag.classify(current) { classifyDrag($0) })
            isPictureDropTargeted = pictureDrag.holds(Self.fieldDragKey) && searchFieldAcceptsDrag
        }
    }

    /// The drag ended (dropped anywhere, or cancelled): the well closes at once.
    func pictureDragEnded() {
        pictureDrag.sessionEnded()
        closeDropWell()
    }

    private func closeDropWell() {
        dragLookup?.cancel()
        dragLookup = nil
        pictureDrag.reset()
        pictureDropState = .none
        isPictureDropTargeted = false
    }

    /// The file URLs on a drag pasteboard, in order.
    private static func draggedFiles(on pasteboard: NSPasteboard) -> [URL] {
        pasteboard.readObjects(forClasses: [NSURL.self], options: [.urlReadingFileURLsOnly: true]) as? [URL] ?? []
    }

    private func classifyDrag(_ pasteboard: NSPasteboard) -> LookoutPictureDrop? {
        // DOKK's own dock-item drags rearrange the dock; the field has nothing to say about them.
        guard pasteboard.string(forType: DockDragCoordinator.pasteboardType) == nil else { return nil }
        let urls = Self.draggedFiles(on: pasteboard)
        let hasImageData = pasteboard.availableType(from: Self.pictureTypes) != nil
        let hits = isPictureSearch ? pictureResults.all : lookoutResults.all
        let names = isPictureSearch ? [] : searchResults
        let fromResults = pictureDrag.origin == .searchResult
        let indexed = similarIndexed
        return LookoutPictureDrop.classify(urls: urls, hasImageData: hasImageData,
                                           fromFilesPane: pictureDrag.origin == .filesPane, options: similarOptions,
                                           inIndex: { indexed[$0.path] }) { url in
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
