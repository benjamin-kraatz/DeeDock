//
//  ContentView.swift
//  Rattention
//
//  Created by Benjamin Kraatz on 26.09.26.
//

import SwiftUI

struct ContentView: View {
    var body: some View {
        VStack(spacing: 16) {
            Button("Request informational attention") {
                runAfter(1_200) {
                    NSApplication.shared.requestUserAttention(.informationalRequest)
                }            }
            Button("Request critical attention") {
                runAfter(1_200) {
                    NSApplication.shared.requestUserAttention(.criticalRequest)
                }
            }
            .tint(.red)
        }
        .controlSize(.large)
        .buttonStyle(.glassProminent)
        .padding()
    }
}

func runAfter(_ ms: Int, _ closure: @escaping @MainActor () -> Void) {
    Task { @MainActor in
        if ms > 0 {
            try? await Task.sleep(for: .milliseconds(ms))
        }

        closure()
    }
}

#Preview {
    ContentView()
}
