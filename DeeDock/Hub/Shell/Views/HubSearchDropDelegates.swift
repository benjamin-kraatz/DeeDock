import SwiftUI

/// Watches drags over the whole Hub for the visible tab's search field (`HubSearchExtras`), and takes none of them.
///
/// It's the outermost drop target, so a region that handles drags itself (a folder row, a pane, the Apps tab's file
/// drop) still gets them first; this one only hears about the parts of the Hub nothing else wants. Every proposal is
/// `.forbidden`, which AppKit treats as no target at all, so dropping outside the field does what it did before.
struct HubDragObserver: DropDelegate {
    let extras: any HubSearchExtras

    func validateDrop(info: DropInfo) -> Bool { true }
    func dropEntered(info: DropInfo) { extras.hubDragChanged(inside: true) }
    func dropUpdated(info: DropInfo) -> DropProposal? { DropProposal(operation: .forbidden) }
    func dropExited(info: DropInfo) { extras.hubDragChanged(inside: false) }
    func performDrop(info: DropInfo) -> Bool { false }
}

/// The search field as a drop target: it takes what the tab accepts (`searchFieldAcceptsDrag`) and refuses the rest,
/// and reports while a drag is over it so the well can light up.
struct HubSearchFieldDropDelegate: DropDelegate {
    let extras: any HubSearchExtras

    // Always valid, so entering and leaving are reported even for a drag the field refuses: the well says why.
    func validateDrop(info: DropInfo) -> Bool { true }
    func dropEntered(info: DropInfo) { extras.searchFieldDragTargeted(true) }

    func dropUpdated(info: DropInfo) -> DropProposal? {
        DropProposal(operation: extras.searchFieldAcceptsDrag ? .copy : .forbidden)
    }

    func dropExited(info: DropInfo) { extras.searchFieldDragTargeted(false) }

    func performDrop(info: DropInfo) -> Bool {
        let taken = extras.searchFieldAcceptsDrag && extras.searchFieldPerformDrop()
        extras.searchFieldDragTargeted(false)
        return taken
    }
}
