import Foundation
import Observation

@MainActor @Observable
final class DockModePickerState {
    let modes: [DockMode]
    let activeModeID: UUID
    var selectedID: UUID?
    @ObservationIgnored var choose: ((UUID) -> Void)?

    init(modes: [DockMode], activeModeID: UUID) {
        self.modes = modes
        self.activeModeID = activeModeID
        selectedID = activeModeID
    }

    func select(by distance: Int) {
        guard !modes.isEmpty else { return }
        let index = selectedID.flatMap { id in modes.firstIndex(where: { $0.id == id }) } ?? 0
        selectedID = modes[min(max(0, index + distance), modes.count - 1)].id
    }

    func chooseSelection() {
        guard let selectedID else { return }
        choose?(selectedID)
    }
}
