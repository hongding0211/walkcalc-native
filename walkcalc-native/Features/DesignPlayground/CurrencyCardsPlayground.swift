#if DEBUG
import SwiftUI

// The Canvas now exercises the production overview and its real data adapter.
private struct CurrencyCardsPage: View {
    @StateObject private var store = CurrencyCardsFixture.makeStore()
    @State private var path = [CurrencyCardsFixture.groupID]
    @WalletAppearanceSettings private var appearance: WalletAppearance

    var body: some View {
        NavigationStack(path: $path) {
            SoftLedgerBackground()
                .navigationDestination(for: String.self) { groupID in
                    GroupView(groupId: groupID)
                }
        }
        .modifier(WalletPreviewAppearance())
        .environmentObject(store)
        .environment(\.softLedgerAppTheme, store.selectedTheme)
        .softLedgerUIKitTint(store.selectedTheme)
        .safeAreaInset(edge: .bottom, spacing: 0) {
            WalletTuningPanel(appearance: $appearance)
        }
    }
}

@MainActor
private enum CurrencyCardsFixture {
    static let groupID = "currency-card-preview"

    static func makeStore() -> WalkcalcStore {
        let store = WalkcalcStore()
        store.applyDebugFixture(.empty)
        store.user?.avatar = ""
        let me = "fixture-current-user"
        let lin = "currency-preview-lin"
        let ming = "currency-preview-ming"
        let now = Date().timeIntervalSince1970 * 1000

        func projection(_ code: String, _ debt: String, _ share: String,
                        _ paid: String, _ count: Int) -> MemberCurrencyProjection {
            MemberCurrencyProjection(currencyCode: code, debtMinor: debt,
                costMinor: share, paidTotalMinor: paid, recordCount: count,
                settlementInMinor: "0", settlementOutMinor: "0")
        }
        let myCurrencies = [
            projection("CNY", "-30000", "120000", "90000", 2),
            projection("THB", "80000", "680000", "760000", 2),
            projection("SGD", "0", "24500", "24500", 1)
        ]
        let members = [
            Member(uuid: me, name: "Hong", avatar: "", debtMinor: "-30000",
                   costMinor: "120000", recordCount: 5, currencyBalances: myCurrencies),
            Member(uuid: lin, name: "Lin", avatar: "", debtMinor: "30000",
                   costMinor: "120000", recordCount: 3, currencyBalances: [
                    projection("CNY", "30000", "120000", "150000", 2),
                    projection("SGD", "0", "24500", "24500", 1)
                   ]),
            Member(uuid: ming, name: "Ming", avatar: "", debtMinor: "0",
                   costMinor: "0", recordCount: 2, currencyBalances: [
                    projection("THB", "-80000", "680000", "600000", 2)
                   ])
        ]
        var group = WalkGroup(id: groupID, name: "旅行账本", currencyCode: "CNY",
                              createdAt: now, modifiedAt: now, membersInfo: members,
                              tempUsers: [], archivedUsers: [], ownerUserId: me, isOwner: true)
        group.hasCurrentUserBalanceSummary = true
        group.currentUserBalanceMinor = "-30000"
        group.currentUserExpenseShareMinor = "120000"
        group.currentUserPaidTotalMinor = "90000"
        group.currentUserCurrencyBalances = myCurrencies
        group.currentUserRecordCount = 5
        group.participantCount = members.count
        group.participantPreview = members
        group.serverHasUnresolvedBalance = true
        store.groups = [group]

        func record(_ id: String, _ payer: String, _ amount: String, _ people: [String],
                    _ code: String, _ category: String, _ note: String, _ hours: Double) -> WalkRecord {
            WalkRecord(recordId: id, who: payer, paidMinor: amount, forWhom: people,
                       type: category, text: note, long: "", lat: "", createdAt: now,
                       occurredAt: now - hours * 3_600_000, modifiedAt: now,
                       isDebtResolve: false, currencyCode: code)
        }
        // Expense shares, payments, and suggested settlements reconcile per currency.
        store.recordsByGroup[groupID] = [
            record("currency-1", lin, "150000", [me, lin], "CNY", "accommodation", "酒店", 0),
            record("currency-2", me, "90000", [me, lin], "CNY", "food", "晚餐", 2),
            record("currency-3", me, "760000", [me, ming], "THB", "accommodation", "曼谷住宿", 26),
            record("currency-4", ming, "600000", [me, ming], "THB", "transport", "包车", 29),
            record("currency-5", me, "24500", [me], "SGD", "food", "餐饮", 50),
            record("currency-6", lin, "24500", [lin], "SGD", "food", "餐饮", 52)
        ]
        store.recordTotals[groupID] = 6
        store.setPreviewSettlementSuggestions([
            SettlementTransfer(fromId: me, toId: lin, amountMinor: "30000", currencyCode: "CNY"),
            SettlementTransfer(fromId: ming, toId: me, amountMinor: "80000", currencyCode: "THB")
        ], groupId: groupID)
        return store
    }
}

#Preview("流体卡包") {
    CurrencyCardsPage()
}
#endif
