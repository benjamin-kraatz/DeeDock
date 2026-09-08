//
//  TrailingSwitchToggleStyle.swift
//  DeeDock
//
//  Created by Benjamin Kraatz on 08.09.26.
//

import SwiftUI


struct TrailingSwitchToggleStyle: ToggleStyle {
    func makeBody(configuration: Configuration) -> some View {
        HStack {
            configuration.label
                .accessibilityHidden(true)
            Spacer()
            Toggle(configuration)
                .labelsHidden()
                .toggleStyle(.switch)
                .controlSize(.small)
        }
    }
}
