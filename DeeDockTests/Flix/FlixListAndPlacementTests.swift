import Foundation
import Testing
@testable import DeeDock

/// The list builder's noise, search, and version rules, and where the panel goes on screen.
@MainActor
struct FlixListAndPlacementTests {
    private let now = Date(timeIntervalSince1970: 1_800_000_000)

    private func item(_ name: String, minutes: Double, folder: String = "/Users/x/Documents") -> FlixItem {
        FlixItem(path: folder + "/" + name, name: name, kind: .document, activity: .opened,
                 date: now.addingTimeInterval(-minutes * 60))
    }

    @Test func noiseIsHiddenAndCounted() {
        let items = [item("Report.pdf", minutes: 1), item("Report.pdf.download", minutes: 2, folder: "/Users/x/Downloads")]
        let hidden = FlixListBuilder.build(FlixListInput(items: items, now: now))
        #expect(hidden.count == 1 && hidden.noiseCount == 1)
        let shown = FlixListBuilder.build(FlixListInput(items: items, showNoise: true, now: now))
        #expect(shown.count == 2)
        #expect(shown.sections.flatMap(\.rows).last?.isNoise == true)
        let off = FlixListBuilder.build(FlixListInput(items: items, hidesNoise: false, now: now))
        #expect(off.count == 2 && off.noiseCount == 0)
    }

    @Test func nameSearchNarrowsTheList() {
        let items = [item("Invoice-11.pdf", minutes: 1), item("Budget.numbers", minutes: 2)]
        let result = FlixListBuilder.build(FlixListInput(items: items, searchText: "invoice", searchActive: true, now: now))
        #expect(result.order == [items[0].id])
        #expect(result.sections.first?.rows.first?.match == .name)
    }

    @Test func olderVersionsFoldUnderTheNewest() {
        let v3 = item("Contract v3.docx", minutes: 30)
        let v2 = item("Contract v2.docx", minutes: 3_000)
        let signed = item("Signed contract.pdf", minutes: 5)
        let annotations: [FlixItem.ID: FlixItemAnnotation] = [
            signed.id: FlixItemAnnotation(versionGroup: "contract", versionRank: 3),
            v3.id: FlixItemAnnotation(versionGroup: "contract", versionRank: 2),
            v2.id: FlixItemAnnotation(versionGroup: "contract", versionRank: 1),
        ]
        var input = FlixListInput(items: [signed, v3, v2], annotations: annotations, now: now)
        let folded = FlixListBuilder.build(input)
        #expect(folded.count == 1)
        #expect(folded.sections.first?.rows.first?.versionCount == 3)
        input.expandedVersions = ["contract"]
        let expanded = FlixListBuilder.build(input)
        #expect(expanded.order == [signed.id, v3.id, v2.id])
        #expect(expanded.sections.first?.rows.dropFirst().allSatisfy(\.isChild) == true)
    }

    @Test func sectionsComeInTimeOrder() {
        let items = [item("a", minutes: 2), item("b", minutes: 90), item("c", minutes: 60 * 24 * 3)]
        let result = FlixListBuilder.build(FlixListInput(items: items, now: now))
        #expect(result.sections.map(\.group) == result.sections.map(\.group).sorted())
        #expect(result.sections.first?.group == .justNow)
        #expect(result.sections.last?.group == .earlier)
    }

    @Test func theAnchoredPanelSitsAboveABottomTileInsideTheScreen() {
        let screen = CGRect(x: 0, y: 0, width: 1512, height: 945)
        let visible = CGRect(x: 0, y: 0, width: 1512, height: 920)
        let tile = CGRect(x: 1400, y: 10, width: 50, height: 50)
        let placement = FlixPanelGeometry.anchored(tile: tile, edge: .bottom, visibleFrame: visible)
        #expect(placement.body.size == FlixPanelGeometry.idealSize)
        #expect(placement.body.minY == tile.maxY + FlixPanelGeometry.tileGap)
        #expect(placement.body.maxX <= visible.maxX - FlixPanelGeometry.screenInset)
        #expect(screen.contains(placement.body))
        #expect(placement.growth.y == 1)
        #expect(placement.growth.x > 0.5)
    }

    @Test func aSideDockOpensBesideTheTile() {
        let visible = CGRect(x: 70, y: 0, width: 1400, height: 900)
        let tile = CGRect(x: 10, y: 400, width: 50, height: 50)
        let placement = FlixPanelGeometry.anchored(tile: tile, edge: .left, visibleFrame: visible)
        #expect(placement.body.minX == max(tile.maxX + FlixPanelGeometry.tileGap, visible.minX + FlixPanelGeometry.screenInset))
        #expect(placement.growth.x == 0)
    }

    @Test func theShortcutOpensAtThePointerOnADisplayLeftOfTheMainOne() {
        // A display arranged to the left and below: negative origin on both axes.
        let visible = CGRect(x: -1920, y: -300, width: 1920, height: 1050)
        let pointer = CGPoint(x: -1900, y: 700)
        let placement = FlixPanelGeometry.atPointer(pointer, visibleFrame: visible)
        #expect(visible.contains(placement.body))
        #expect(placement.body.minX == visible.minX + FlixPanelGeometry.screenInset)
        #expect(placement.body.maxY == min(pointer.y + 80, visible.maxY - FlixPanelGeometry.screenInset))
    }

    @Test func aSmallScreenShrinksThePanel() {
        let visible = CGRect(x: 0, y: 0, width: 600, height: 420)
        let size = FlixPanelGeometry.size(in: visible)
        #expect(size.width == 584 && size.height == 404)
        let tiny = FlixPanelGeometry.size(in: CGRect(x: 0, y: 0, width: 300, height: 200))
        #expect(tiny == FlixPanelGeometry.minimumSize)
    }

    @Test func theReadPolicyNeverReadsProtectedFoldersUnlessAllowed() {
        let policy = FlixReadPolicy(home: "/Users/x", allowedRoots: ["/Users/x/Downloads", "/Users/x/Documents/Clients"])
        #expect(policy.canRead("/Users/x/Downloads/a.pdf"))
        #expect(policy.canRead("/Users/x/Documents/Clients/Oak/a.pdf"))
        #expect(!policy.canRead("/Users/x/Documents/ClientsOld/a.pdf"))
        #expect(!policy.canRead("/Users/x/Documents/a.pdf"))
        #expect(policy.canRead("/Users/x/Projects/a.swift"))
        #expect(!policy.canRead("/Volumes/Backup/a.pdf"))
        #expect(!policy.canRead("/Users/x/Library/Mobile Documents/com~apple~CloudDocs/a.key"))
    }
}
