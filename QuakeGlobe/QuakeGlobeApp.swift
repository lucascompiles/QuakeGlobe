//
//  QuakeGlobeApp.swift
//  QuakeGlobe
//
//  Created by Lucas on 14/08/26.
//

import SwiftUI
import SwiftData

@main
struct QuakeGlobeApp: App {
    var body: some Scene {
        WindowGroup {
            ContentView()
        }
        .modelContainer(for: FavoriteQuake.self)
    }
}
