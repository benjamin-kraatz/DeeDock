import Foundation
import Testing
@testable import DeeDock

/// Folder results: three or more matching direct children make a folder, scored as the average of its best three plus
/// 0.25 a file beyond them, the bonus capped at 1.
struct LookoutFolderGroupingTests {
    @Test func theScoreAveragesTheBestThreeAndCapsTheBonus() {
        #expect(LookoutFolderGrouping.score(fileScores: [1, 3, 2]) == 2)
        #expect(LookoutFolderGrouping.score(fileScores: [3, 2, 1, 0.5]) == 2.25)
        #expect(LookoutFolderGrouping.score(fileScores: [5, 4, 3, 1, 1, 1, 1, 1, 1]) == 5)   // 6 × 0.25 capped at 1
        #expect(LookoutFolderGrouping.score(fileScores: [5, 4, 3, 1, 1, 1, 1]) == 5)   // exactly at the cap
    }

    @Test func onlyDirectChildrenCountAndTheExcludedFolderIsSkipped() {
        func member(_ path: String, _ score: Double, _ match: LookoutHit.Match = .words) -> LookoutFolderGrouping.Member {
            .init(path: path, score: score, z: nil, coverage: 1, match: match)
        }
        let members = [member("/r/a/1", 3), member("/r/a/2", 2), member("/r/a/deep/3", 1),
                       member("/r/b/1", 3, .meaning), member("/r/b/2", 2), member("/r/b/3", 1),
                       member("/r/c/1", 1), member("/r/c/2", 1), member("/r/c/3", 1)]
        let folders = LookoutFolderGrouping.folders(from: members, excluding: "/r/c/")
        #expect(folders.map(\.path) == ["/r/b"])
        let folder = folders[0]
        #expect(folder.folder == .init(matchingFiles: 3, topFiles: ["/r/b/1", "/r/b/2", "/r/b/3"]))
        #expect(folder.score == 2 && folder.match == .both && folder.isFolder && folder.kind == nil)
    }

    @Test func foldersJoinTheRankedListBesideTheirFiles() throws {
        let index = try LookoutSearchIndex()
        for number in 1...2 { try index.add("two/f\(number).txt", text: "budget") }
        for number in 1...4 { try index.add("four/f\(number).txt", text: "budget") }
        for number in 1...8 { try index.add("eight/f\(number).txt", text: "budget") }
        let results = try index.searcher().search("budget", queryVector: nil, limit: 100)
        let folders = results.all.filter(\.isFolder)
        #expect(folders.map(\.path) == [index.path("eight"), index.path("four")])
        #expect(folders.map(\.score) == [3, 2.25])   // every file scores 2: +1 (capped), +0.25
        #expect(folders.map { $0.folder?.matchingFiles } == [8, 4])
        #expect(Array(results.all.prefix(2)) == folders)   // they outrank their files here
        #expect(results.all.filter { !$0.isFolder }.count == 14)
    }
}
