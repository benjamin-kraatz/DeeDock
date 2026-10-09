import Foundation
import Testing
@testable import DeeDock

struct HubFileSortTests {
    private func item(_ name: String, folder: Bool = false, size: Int64? = nil, modified: TimeInterval = 0,
                      kind: String = "Document") -> HubFileItem {
        HubFileItem(url: URL(fileURLWithPath: "/tmp/sort/\(name)"), name: name, isDirectory: folder, isPackage: false,
                    isHidden: false, contentType: nil, byteSize: folder ? nil : (size ?? 0),
                    modified: Date(timeIntervalSince1970: modified), created: nil, volumeIdentifier: nil,
                    kindDescription: folder ? "Folder" : kind)
    }

    private func names(_ items: [HubFileItem], _ sort: HubFileSort) -> [String] {
        sort.sorted(items).map(\.name)
    }

    @Test func nameSortKeepsFoldersOnTopInBothDirections() {
        let items = [item("b.txt"), item("Zeta", folder: true), item("a.txt"), item("Alpha", folder: true)]
        #expect(names(items, HubFileSort()) == ["Alpha", "Zeta", "a.txt", "b.txt"])
        #expect(names(items, HubFileSort(key: .name, ascending: false)) == ["Zeta", "Alpha", "b.txt", "a.txt"])
    }

    @Test func nameSortUsesLocalizedStandardCompare() {
        let items = [item("File 10"), item("file 2"), item("File 1")]
        #expect(names(items, HubFileSort()) == ["File 1", "file 2", "File 10"])
    }

    @Test func modifiedSortMixesFoldersAndFiles() {
        let items = [item("old", modified: 1), item("dir", folder: true, modified: 3), item("new", modified: 2)]
        #expect(names(items, HubFileSort(key: .modified, ascending: false)) == ["dir", "new", "old"])
        #expect(names(items, HubFileSort(key: .modified)) == ["old", "new", "dir"])
    }

    @Test func sizeSortPutsFoldersBelowEmptyFiles() {
        let items = [item("big", size: 900), item("dir", folder: true), item("empty", size: 0), item("mid", size: 40)]
        #expect(names(items, HubFileSort(key: .size)) == ["dir", "empty", "mid", "big"])
        #expect(names(items, HubFileSort(key: .size, ascending: false)) == ["big", "mid", "empty", "dir"])
    }

    @Test func kindSortBreaksTiesByName() {
        let items = [item("b", kind: "PDF document"), item("a", kind: "PDF document"), item("c", kind: "JPEG image")]
        #expect(names(items, HubFileSort(key: .kind)) == ["c", "a", "b"])
        #expect(names(items, HubFileSort(key: .kind, ascending: false)) == ["a", "b", "c"])
    }
}
