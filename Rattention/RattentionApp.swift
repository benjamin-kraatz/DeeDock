//
//  RattentionApp.swift
//  Rattention
//
//  Created by Benjamin Kraatz on 26.09.26.
//

import SwiftUI

@main
struct RattentionApp: App {
    var body: some Scene {
        WindowGroup {
            ContentView()
                .task { await AttentionProbe.runIfRequested() }
        }
    }
}
