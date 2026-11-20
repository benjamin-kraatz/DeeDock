import SwiftUI

/// The panel's right side: header, list, footer, and the sheet over them.
struct FlixMainColumn: View {
    let state: FlixPanelState

    var body: some View {
        let list = state.list
        VStack(spacing: 0) {
            FlixHeaderView(state: state, count: list.count)
            Divider().opacity(0.6)
            FlixListView(state: state, list: list)
            Divider().opacity(0.6)
            FlixFooterView(state: state, noiseCount: list.noiseCount)
        }
        .overlay { FlixSheetLayer(state: state) }
    }
}
