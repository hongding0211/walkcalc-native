//
//  walkcalc_nativeApp.swift
//  walkcalc-native
//
//  Created by hong on 2026/5/9.
//

import SwiftUI

@main
struct walkcalc_nativeApp: App {
    @UIApplicationDelegateAdaptor(WalkcalcAppDelegate.self) private var appDelegate
    @StateObject private var store = WalkcalcStore()

    init() {
        UIView.appearance().tintColor = SoftLedgerTheme.accentUIColor

        #if DEBUG
        if ProcessInfo.processInfo.arguments.contains("--verify-temporal-display") {
            TemporalDisplayVerification.assertAllCasesPass()
        }
        if ProcessInfo.processInfo.arguments.contains("--verify-money-display") {
            MoneyDisplayVerification.assertAllCasesPass()
        }
        if ProcessInfo.processInfo.arguments.contains("--verify-ledger-migration") {
            LedgerMigrationVerification.assertAllCasesPass()
        }
        if ProcessInfo.processInfo.arguments.contains("--verify-api-contract") {
            LedgerAPIContractVerification.assertAllCasesPass()
        }
        #endif
    }

    var body: some Scene {
        WindowGroup {
            #if DEBUG
            if ProcessInfo.processInfo.arguments.contains("--design-playground-home") {
                SoftLedgerGroupHomePlayground()
            } else if ProcessInfo.processInfo.arguments.contains("--design-playground-detail") {
                GroupDetailPreviewHost()
            } else if ProcessInfo.processInfo.arguments.contains("--design-playground-settlement") {
                SettlementPlanPlayground()
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
