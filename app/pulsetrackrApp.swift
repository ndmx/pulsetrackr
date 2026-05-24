//
//  pulsetrackrApp.swift
//  pulsetrackr
//
//  Created by Alexander Ukaga on 8/14/25.
//

import SwiftUI

@main
struct pulsetrackrApp: App {
    init() {
        FirebaseBootstrap.configureIfAvailable()
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
        }
    }
}
