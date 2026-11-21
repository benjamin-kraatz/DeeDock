import Carbon
import Foundation
import Testing
import UniformTypeIdentifiers
@testable import DeeDock

/// Flix Files' analytics: event names and properties, the on-device reductions (app categories,
/// page kinds, shortcut tokens, folders), the per-open session accumulator, and that names and
/// text never reach a property.
@MainActor
struct FlixAnalyticsTests {
    private let opened = Date(timeIntervalSince1970: 1_800_000_000)
    /// What a PDF reports as: `com.adobe.pdf` is not Apple's, so it is reduced to a system ancestor.
    private let pdf = AnalyticsFileType(UTType.pdf)?.identifier ?? ""

    private func file(_ name: String, minutes: Double = 5, kind: FlixItemKind = .document,
                      activity: FlixActivity = .downloaded) -> FlixItem {
        FlixItem(path: "/Users/x/Documents/" + name, name: name, kind: kind, activity: activity,
                 date: opened.addingTimeInterval(-minutes * 60), contentTypeIdentifier: "com.adobe.pdf")
    }

    private func record() -> FlixSessionRecord {
        FlixSessionRecord(trigger: .shortcut, placement: .pointer, displayBuiltin: true, openedAt: opened,
                          frontCategory: .browser, unseenAtOpen: 2, listSizeAtOpen: 40)
    }

    /// Every text value in a record's payload, so a test can say none of them is a name.
    private func texts(_ record: AnalyticsRecord) -> [String] {
        record.properties.payload.values.flatMap { value -> [String] in
            if let text = value as? String { return [text] }
            return value as? [String] ?? []
        }
    }

    // MARK: Events

    @Test func sessionEndedCarriesTheVisitAsTokensAndNumbers() {
        var visit = record()
        visit.record(.quickLook, item: file("Invoice.pdf", minutes: 90), place: (.stream, 3),
                     at: opened.addingTimeInterval(1.5))
        visit.record(.drag, item: file("Invoice.pdf"), place: (.stream, 3), at: opened.addingTimeInterval(4))
        visit.filterChanged(to: .kind(.documents))
        visit.scrolled(rows: 7)
        let event = AnalyticsEvent.flixSessionEnded(visit.session(endedAt: opened.addingTimeInterval(6),
                                                                  closedBy: .other, pinned: true)).record
        #expect(event.name == "flix_session_ended")
        #expect(event.properties["trigger"] == AnalyticsValue(AnalyticsFlixTrigger.shortcut))
        #expect(event.properties["front_category"] == AnalyticsValue(FlixAppCategory.browser))
        #expect(event.properties["outcome"] == AnalyticsValue(AnalyticsFlixOutcome.draggedOut))
        #expect(event.properties["duration_ms"] == AnalyticsValue(6_000))
        #expect(event.properties["time_to_first_action_ms"] == AnalyticsValue(1_500))
        #expect(event.properties["first_action_section"] == AnalyticsValue(AnalyticsFlixSection.stream))
        #expect(event.properties["first_action_rank"] == AnalyticsValue(3))
        #expect(event.properties["first_action_item_event"] == AnalyticsValue(AnalyticsFlixItemEvent.downloaded))
        #expect(event.properties["first_action_item_age_minutes"] == AnalyticsValue(90))
        #expect(event.properties["first_action_item_kind"]?.displayText == pdf)
        #expect(event.properties["quick_looks"] == AnalyticsValue(1))
        #expect(event.properties["drags"] == AnalyticsValue(1))
        #expect(event.properties["filter_changes"] == AnalyticsValue(1))
        #expect(event.properties["sidebar_areas_used"] == AnalyticsValue(1))
        #expect(event.properties["max_scrolled_rows"] == AnalyticsValue(7))
        #expect(event.properties["pinned"] == AnalyticsValue(true))
        #expect(event.properties["fits_reader"] == nil)
    }

    @Test func dropListsKindsOnceAndNamesNoFile() {
        let items = [file("Passport scan.pdf"), file("Bank details.pdf"),
                     FlixItem(path: "/Users/x/Clients", name: "Clients", kind: .folder, activity: .opened, date: opened)]
        let drop = AnalyticsFlixDrop(items: items, source: .fits, place: (.fits, 1), target: .browserUpload,
                                     targetCategory: .browser, pageKind: .uploadForm, plan: nil, warning: .sensitive,
                                     resolution: .sendAnyway, pinned: false, predicted: true)
        let event = AnalyticsEvent.flixDrop(drop).record
        #expect(event.name == "flix_drop")
        #expect(event.properties["item_kinds"]?.displayText == pdf + ", folder")
        #expect(event.properties["contains_folder"] == AnalyticsValue(true))
        #expect(event.properties["target"] == AnalyticsValue(AnalyticsFlixDropTarget.browserUpload))
        #expect(event.properties["warning_resolution"] == AnalyticsValue(AnalyticsFlixWarningResolution.sendAnyway))
        #expect(event.properties["converted"] == AnalyticsValue(false))
        #expect(event.properties["convert_ms"] == nil)
        #expect(!texts(event).contains { $0.contains("Passport") || $0.contains("Bank") || $0.contains("Clients") })
    }

    @Test func smallEventsUseTheirSpecNames() {
        let names = [
            AnalyticsEvent.flixTidy(AnalyticsFlixTidy(shownMoves: 2, shownRenames: 1)).record.name,
            AnalyticsEvent.flixSuggestionActed(.rename, action: .undone, itemKind: .folder).record.name,
            AnalyticsEvent.flixSmartFilterCreated(source: .tip, ruleKinds: [.location], matchCount: 4, generator: nil).record.name,
            AnalyticsEvent.flixSmartFilterRemoved(source: .sentence).record.name,
            AnalyticsEvent.flixThreadUsed(.dragCard, threadSize: 5, namedBy: .folder).record.name,
            AnalyticsEvent.flixMorningCard(.ignored, threadCount: 2).record.name,
            AnalyticsEvent.flixMoreLikeThis(resultCount: 3, outcome: .none, itemKind: nil).record.name,
            AnalyticsEvent.flixSensitiveMarkedSafe(itemKind: nil).record.name,
            AnalyticsEvent.flixVersionsExpanded(versionCount: 3).record.name,
            AnalyticsEvent.flixLinkSaved(.savedButton, pageKind: .webDocument).record.name,
            AnalyticsEvent.flixFolderAccess(.denied, folder: .downloads).record.name,
            AnalyticsEvent.flixTipShown(.discovery).record.name,
            AnalyticsEvent.flixTipActed(.smartFilter, action: .accepted).record.name,
        ]
        #expect(names == ["flix_tidy", "flix_suggestion_acted", "flix_smart_filter_created", "flix_smart_filter_removed",
                          "flix_thread_used", "flix_morning_card", "flix_more_like_this", "flix_sensitive_marked_safe",
                          "flix_versions_expanded", "flix_link_saved", "flix_folder_access", "flix_tip_shown",
                          "flix_tip_acted"])
    }

    @Test func robiAndSearchSendMetadataOnly() {
        let robi = AnalyticsEvent.flixRobiAsked(AnalyticsFlixRobi(
            question: AnalyticsFlixRobiQuestion(suggestionIndex: 1), selectionCount: 2,
            itemKinds: [file("Quote.pdf"), file("Quote v2.pdf")].analyticsKinds, latencyMs: 812, result: .noKey)).record
        #expect(robi.name == "flix_robi_asked")
        #expect(robi.properties["question"] == AnalyticsValue(AnalyticsFlixRobiQuestion.suggested2))
        #expect(robi.properties["item_kinds"]?.displayText == pdf)
        #expect(robi.properties["result"] == AnalyticsValue(AnalyticsFlixRobiResult.noKey))
        #expect(AnalyticsFlixRobiQuestion(suggestionIndex: nil) == .typed)
        #expect(AnalyticsFlixRobiQuestion(suggestionIndex: 7) == .typed)

        let search = AnalyticsEvent.flixSearchEnded(AnalyticsFlixSearch(
            queryWordCount: 4, tokenCount: 2, tokenTypes: [.time, .about], tokensRemoved: [.time], parser: .rules,
            parseMs: 12, resultCount: 6, byMeaningCount: 2, lookoutAvailable: true, outcome: .dragged, chosenRank: 1,
            chosenMatch: .meaning)).record
        #expect(search.name == "flix_search_ended")
        #expect(search.properties["token_types"]?.displayText == "time, about")
        #expect(search.properties["chosen_match"] == AnalyticsValue(AnalyticsFlixMatch.meaning))
    }

    @Test func fitsComputedReportsCountsAndTheReader() {
        let reading = FlixWindowReading(text: "", chain: FlixReaderChain(steps: [.accessibility, .vision], succeeded: true))
        #expect(FlixFitsProvider.reader(for: reading) == .vision)
        #expect(FlixFitsProvider.reader(for: FlixWindowReading(text: "", chain: FlixReaderChain())) == .noPermission)
        #expect(FlixFitsProvider.reader(for: FlixWindowReading(text: "", chain: FlixReaderChain(steps: [.accessibility])))
                == .none)
        #expect(FlixWindowReading.wordCount("Upload  your signed\ncontract") == 4)
        let event = AnalyticsEvent.flixFitsComputed(AnalyticsFlixFits(
            reader: .vision, stepsTried: 2, axWords: 3, ocrWords: 120, intentItems: 1, hasTypeLimit: true,
            hasSizeLimit: false, matches: 2, readyMs: 640, frontCategory: .browser, pageKind: .uploadForm)).record
        #expect(event.name == "flix_fits_computed")
        #expect(event.properties["ocr_words"] == AnalyticsValue(120))
        #expect(event.properties["page_kind"] == AnalyticsValue(AnalyticsFlixPageKind.uploadForm))
    }

    // MARK: On-device reductions

    @Test func appCategoriesComeFromWhatAnAppDeclares() {
        #expect(FlixAppCategory.allCases.map(\.rawValue)
                == ["browser", "mail", "chat", "office", "design", "developer", "finder", "other", "none"])
        #expect(FlixAppCategory.from(appStoreCategory: "public.app-category.social-networking") == .chat)
        #expect(FlixAppCategory.from(appStoreCategory: "public.app-category.business") == .office)
        #expect(FlixAppCategory.from(appStoreCategory: "public.app-category.photography") == .design)
        #expect(FlixAppCategory.from(appStoreCategory: "public.app-category.developer-tools") == .developer)
        #expect(FlixAppCategory.from(appStoreCategory: "public.app-category.games") == .other)
        #expect(FlixAppCategory.of(bundleIdentifier: "com.apple.finder", bundleURL: nil) == .finder)
        #expect(FlixAppCategory.of(bundleIdentifier: nil, bundleURL: nil) == FlixAppCategory.none)
    }

    @Test func pageKindsAndFoldersHideTheAddress() {
        #expect(AnalyticsFlixPageKind(url: URL(string: "https://docs.google.com/document/d/abc/edit")!) == .webDocument)
        #expect(AnalyticsFlixPageKind(url: URL(string: "https://mail.google.com/mail/u/0/")!) == .webmail)
        #expect(AnalyticsFlixPageKind(url: URL(string: "https://www.icloud.com/mail/")!) == .webmail)
        #expect(AnalyticsFlixPageKind(url: URL(string: "https://portal.example.com/upload")!) == .otherPage)
        #expect(AnalyticsFlixPageKind(.upload) == .uploadForm)
        #expect(AnalyticsFlixFolder(path: "/Users/x/Downloads", home: "/Users/x") == .downloads)
        #expect(AnalyticsFlixFolder(path: "/Users/x/Library/Mobile Documents/com~apple~CloudDocs", home: "/Users/x")
                == .icloudDrive)
        #expect(AnalyticsFlixFolder(path: "/Users/x/Clients/Oak", home: "/Users/x") == .other)
    }

    @Test func linkCleaningCountsTheCredentialsItRemoves() {
        let url = URL(string: "https://user:pw@files.example.com/a?token=1&X-Amz-Credential=2&page=3&utm_source=x")!
        #expect(FlixURLSanitizer.removedSecretCount(url) == 3)
        #expect(FlixURLSanitizer.removedSecretCount(URL(string: "https://example.com/?q=report")!) == 0)
    }

    @Test func shortcutCombosBecomeClosedTokens() {
        #expect(AnalyticsShortcutCombo(FlixShortcutCombo.default).rawValue == "ctrl_opt_cmd_f")
        let spotlightLike = FlixShortcutCombo(keyCode: UInt16(kVK_Space), modifiers: [.command, .shift])
        #expect(AnalyticsShortcutCombo(spotlightLike).rawValue == "shift_cmd_space")
        #expect(AnalyticsShortcutCombo(FlixShortcutCombo(keyCode: UInt16(kVK_F5), modifiers: [])).rawValue == "f5")
        #expect(AnalyticsShortcutCombo(FlixShortcutCombo(keyCode: UInt16(kVK_ISO_Section), modifiers: [.option])).rawValue
                == "opt_other")
        #expect(AnalyticsShortcutCombo(rawValue: "ctrl_opt_cmd_f") != nil)
        #expect(AnalyticsShortcutCombo(rawValue: "cmd_ctrl_f") == nil)
        #expect(AnalyticsShortcutCombo(rawValue: "Invoice.pdf") == nil)
        #expect(AnalyticsShortcutCombo(rawValue: "ctrl_secret") == nil)
    }

    @Test func settingsReportCountsAndTheShortcutNeverPaths() {
        var before = FlixSettings()
        before.watchedFolders = [FlixWatchedFolder(path: "/Users/x/Downloads")]
        before.excludedSites = []
        var after = before
        after.watchedFolders.append(FlixWatchedFolder(path: "/Users/x/Clients/Oak & Ash"))
        after.excludedSites = ["bank.example.com"]
        after.shortcut = FlixShortcutCombo(keyCode: UInt16(kVK_ANSI_D), modifiers: [.control, .option])
        let properties = after.analyticsProperties
        #expect(properties["watched_folder_count"] == AnalyticsValue(2))
        #expect(properties["excluded_site_count"] == AnalyticsValue(1))
        #expect(properties["shortcut_customized"] == AnalyticsValue(true))
        #expect(properties["shortcut_combo"]?.displayText == "ctrl_opt_d")
        let changed = AnalyticsSettingChange.changes(from: before.analyticsProperties, to: properties)
            .compactMap { $0.properties["key"]?.displayText }
        #expect(Set(changed) == ["watched_folder_count", "excluded_site_count", "shortcut_customized", "shortcut_combo"])
        let text = properties.payload.values.compactMap { $0 as? String }
        #expect(!text.contains { $0.contains("Oak") || $0.contains("bank") || $0.contains("/Users") })
    }

    @Test func itemKindsAndEventsReduceToTypes() {
        let link = FlixItem(link: FlixLink(url: URL(string: "https://example.com/secret-plan")!, title: "Secret plan",
                                           browserBundleIdentifier: nil),
                            name: "Secret plan", kind: .link, activity: .link, date: opened)
        #expect(link.analyticsKind == .link)
        #expect(link.analyticsEvent == .link)
        let app = FlixItem(path: "/Applications/Notes.app", name: "Notes", kind: .app, activity: .opened, date: opened)
        #expect(app.analyticsEvent == .app)
        #expect(file("Kept.pdf", activity: .kept).analyticsEvent == .saved)
        #expect(file("New.pdf", activity: .created).analyticsEvent == .new)
        // A third-party type is reduced to its nearest system ancestor, never the app's own identifier.
        let sketch = FlixItem(path: "/Users/x/Logo.sketch", name: "Logo.sketch", kind: .document, activity: .saved,
                              date: opened, contentTypeIdentifier: "com.bohemiancoding.sketch.drawing")
        let kind = sketch.analyticsKind?.value.displayText ?? ""
        #expect(!kind.contains("bohemian"))
        #expect(FlixFilter.activity(.all).analyticsSection == .stream)
        #expect(FlixFilter.activity(.flagged).analyticsSection == .flagged)
        #expect(FlixFilter.activity(.downloaded).analyticsSection == .activityFilter)
        #expect(FlixSmartFilterRule.amountOver(1_000).analyticsTokenType == .amount)
        #expect(FlixSmartFilterRule.locationContains("Oak").analyticsRuleKind == .location)
    }

    // MARK: The session accumulator

    @Test func theFirstActionWithAPlaceWinsAndCountsAddUp() {
        var visit = record()
        visit.record(.other, item: file("A.pdf"), place: nil, at: opened.addingTimeInterval(1))
        visit.record(.copy, item: file("B.pdf"), place: (.search, 2), at: opened.addingTimeInterval(2))
        visit.record(.open, item: file("C.pdf"), place: (.stream, 1), at: opened.addingTimeInterval(3))
        visit.record(.flag, item: nil, place: nil, at: opened.addingTimeInterval(4))
        #expect(visit.firstAction?.section == .search)
        #expect(visit.firstAction?.rank == 2)
        #expect(visit.copies == 1 && visit.opens == 1 && visit.flags == 1)
        #expect(visit.outcome(closedBy: .escape) == .opened)
    }

    @Test func outcomesPreferActionsOverHowThePanelClosed() {
        var visit = record()
        #expect(visit.outcome(closedBy: .escape) == .escape)
        #expect(visit.outcome(closedBy: .clickedAway) == .clickedAway)
        #expect(visit.outcome(closedBy: .shortcutToggle) == .shortcutToggle)
        #expect(visit.outcome(closedBy: .other) == .nothing)
        visit.record(.quickLook, item: nil, place: nil, at: opened)
        #expect(visit.outcome(closedBy: .escape) == .quickLookOnly)
        visit.record(.robi, item: nil, place: nil, at: opened)
        #expect(visit.outcome(closedBy: .escape) == .robi)
        visit.record(.reveal, item: nil, place: nil, at: opened)
        #expect(visit.outcome(closedBy: .escape) == .revealed)
    }

    @Test func onlyUsingAFitAcceptsIt() {
        var visit = record()
        visit.record(.quickLook, item: file("A.pdf"), place: (.fits, 1), at: opened)
        visit.record(.flag, item: file("A.pdf"), place: (.fits, 1), at: opened)
        #expect(!visit.fitsAccepted)
        visit.record(.drag, item: file("B.pdf"), place: (.fits, 2), at: opened)
        #expect(visit.fitsAccepted && visit.fitsRank == 2)
    }

    @Test func weekdaysCountFromMondayAndHoursFromTheLocalClock() throws {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = try #require(TimeZone(identifier: "Europe/Berlin"))
        // Sunday, 2026-11-22 08:15 in Berlin.
        let sunday = try #require(calendar.date(from: DateComponents(year: 2026, month: 11, day: 22, hour: 8, minute: 15)))
        let visit = FlixSessionRecord(trigger: .tileClick, placement: .tile, displayBuiltin: false, openedAt: sunday,
                                      frontCategory: .none, unseenAtOpen: 0, listSizeAtOpen: 0)
        let session = visit.session(endedAt: sunday, closedBy: .other, pinned: false, calendar: calendar)
        #expect(session.weekday == 7)
        #expect(session.localHour == 8)
        let next = FlixSessionRecord(trigger: .tileClick, placement: .tile, displayBuiltin: false,
                                     openedAt: sunday.addingTimeInterval(86_400), frontCategory: .none, unseenAtOpen: 0,
                                     listSizeAtOpen: 0)
        #expect(next.session(endedAt: sunday, closedBy: .other, pinned: false, calendar: calendar).weekday == 1)
    }

    @Test func metricsSendOneSessionPerOpenAndIgnoreEverythingOutsideIt() {
        let history = FlixHistory(folder: nil)
        let now = Date.now
        for (index, name) in ["Contract Mike.pdf", "Budget.numbers", "Photo.heic"].enumerated() {
            history.record(FlixActivityEvent(path: "/Users/x/Documents/" + name, name: name, kind: .document,
                                             activity: .opened, date: now.addingTimeInterval(-Double(index) * 60)))
        }
        let panel = FlixPanelState(history: history, intelligence: FlixIntelligence(),
                                   settingsStore: FlixSettingsStore(repository: nil))
        let metrics = FlixSessionMetrics()
        var sent: [AnalyticsRecord] = []
        metrics.send = { sent.append($0.record) }
        metrics.panel = panel
        panel.metrics = metrics

        // Before an open nothing counts.
        metrics.acted(.open, items: history.items, origin: .list)
        metrics.end(reason: .escape, pinned: false)
        #expect(sent.isEmpty)

        metrics.begin(trigger: .shortcut, placement: .pointer, displayBuiltin: true, front: .mail, unseen: 1,
                      listSize: panel.list.count)
        metrics.pointerPressed()
        let second = history.items[1]
        metrics.acted(.copy, items: [second], origin: .list)
        panel.searchText = "contract mike"
        panel.searchText = ""
        metrics.end(reason: .clickedAway, pinned: false)
        metrics.end(reason: .clickedAway, pinned: false)

        #expect(sent.map(\.name) == ["flix_search_ended", "flix_session_ended"])
        let search = sent[0]
        #expect(search.properties["query_word_count"] == AnalyticsValue(2))
        #expect(search.properties["outcome"] == AnalyticsValue(AnalyticsFlixResultOutcome.none))
        #expect(search.properties["result_count"] == AnalyticsValue(1))
        let session = sent[1]
        #expect(session.properties["outcome"] == AnalyticsValue(AnalyticsFlixOutcome.copied))
        #expect(session.properties["keyboard_only"] == AnalyticsValue(false))
        #expect(session.properties["search_used"] == AnalyticsValue(true))
        #expect(session.properties["first_action_section"] == AnalyticsValue(AnalyticsFlixSection.stream))
        #expect(session.properties["first_action_rank"] == AnalyticsValue(2))
        #expect(session.properties["list_size_at_open"] == AnalyticsValue(3))
        #expect(!sent.flatMap(texts).contains { $0.localizedCaseInsensitiveContains("contract") })
    }

    // MARK: Fits scoring

    @Test func meaningLiftsAFileWithoutMatchingWords() {
        let wanted = FlixWindowDemand.Wanted(phrase: "the signed agreement", keywords: ["signed", "agreement"])
        let item = FlixFitCandidate(item: file("Scan 0042.pdf"))
        let keyword = FlixKeywordFitScorer()
        #expect(keyword.score(wanted, item: item, now: opened) < FlixFitRanker.minimumScore)
        let blended = FlixBlendedFitScorer(keyword: keyword, meaning: [wanted.phrase: [item.item.id: 1]])
        #expect(blended.score(wanted, item: item, now: opened) >= FlixFitRanker.minimumScore)
        let weak = FlixBlendedFitScorer(keyword: keyword,
                                        meaning: [wanted.phrase: [item.item.id: FlixBlendedFitScorer.normalized(0.35)]])
        #expect(weak.score(wanted, item: item, now: opened) < FlixFitRanker.minimumScore)
        #expect(FlixBlendedFitScorer.normalized(FlixBlendedFitScorer.floor) == 0)
        #expect(FlixBlendedFitScorer.normalized(0.9) == 1)
    }

    @Test func dragMemoryBreaksATie() {
        let a = file("Contract A.pdf", minutes: 10)
        let b = file("Contract B.pdf", minutes: 10)
        let demand = FlixWindowDemand(wanted: [.init(phrase: "the contract", keywords: ["contract"])])
        let candidates = [a, b].map { FlixFitCandidate(item: $0) }
        let plain = FlixFitRanker.rank(demand: demand, candidates: candidates, scorer: FlixKeywordFitScorer(), now: opened)
        let preferred = plain.last?.itemID
        let ranked = FlixFitRanker.rank(demand: demand, candidates: candidates, scorer: FlixKeywordFitScorer(),
                                        now: opened, preferred: preferred)
        #expect(ranked.first?.itemID == preferred)
    }
}
