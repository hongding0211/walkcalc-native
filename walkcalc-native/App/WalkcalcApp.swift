//
//  walkcalc_nativeApp.swift
//  walkcalc-native
//
//  Created by hong on 2026/5/9.
//

import SwiftUI

@main
struct walkcalc_nativeApp: App {
    @StateObject private var store = WalkcalcStore()

    var body: some Scene {
        WindowGroup {
            #if DEBUG
            if ProcessInfo.processInfo.arguments.contains("--design-playground-home") {
                SoftLedgerGroupHomePlayground()
            } else if ProcessInfo.processInfo.arguments.contains("--design-playground-detail") {
                GroupDetailPreviewHost()
            } else {
                ContentView()
                    .environmentObject(store)
            }
            #else
            ContentView()
                .environmentObject(store)
            #endif
        }
    }
}
