#!/usr/bin/env python3
"""Verify real wallet projections and settlement copy without a server or simulator."""
from pathlib import Path
import subprocess
import tempfile

root = Path(__file__).resolve().parents[1]
app = root / 'walkcalc-native'
models = (app / 'Core/Models/Models.swift').read_text()
ui = (app / 'Shared/UI/SoftLedgerUI.swift').read_text()
source = '''import Foundation
let strings = NSDictionary(contentsOfFile: CommandLine.arguments[1]) as! [String: String]
func L(_ key: String) -> String { strings[key] ?? key }
'''
source += (app / 'Shared/Localization/L10n.swift').read_text().split('func L(')[0]
source += (app / 'Core/Models/Money.swift').read_text()
source += ui[ui.index('enum MoneyDisplayStyle {'):ui.index('func signedMoney(')]
source += models[models.index('struct Member:'):models.index('struct WalkRecord:')]
source += models[models.index('struct ResolvedDebt:'):models.index('struct SettlementTransfer:')]
source += (app / 'Features/Groups/GroupWalletData.swift').read_text()
source += (app / 'Features/Groups/WalletCardOrder.swift').read_text()
source += r'''
func projection(_ code: String, cost: String, debt: String = "0", paid: String = "0", records: Int = 1) -> MemberCurrencyProjection {
    MemberCurrencyProjection(currencyCode: code, debtMinor: debt, costMinor: cost,
        paidTotalMinor: paid, recordCount: records, settlementInMinor: "0", settlementOutMinor: "0")
}
let me = Member(uuid: "me", name: "Me", avatar: "", debtMinor: "-999", costMinor: "777")
let lin = Member(uuid: "lin", name: "Lin", avatar: "", debtMinor: "0", costMinor: "0")
let ming = Member(uuid: "ming", name: "Ming", avatar: "", debtMinor: "0", costMinor: "0")
var group = WalkGroup(id: "g", name: "Trip", currencyCode: "CNY", createdAt: 0, modifiedAt: 0,
    membersInfo: [me, lin, ming], tempUsers: [], archivedUsers: [], isOwner: true,
    hasCurrentUserBalanceSummary: true, currentUserBalanceMinor: "-30000", currentUserExpenseShareMinor: "120000")
group.currentUserCurrencyBalances = [
    projection("CNY", cost: "120000", debt: "-30000", paid: "90000"),
    projection("THB", cost: "680000", debt: "80000", paid: "760000"),
    projection("SGD", cost: "24500")]
let debts = [ResolvedDebt(from: me, to: lin, amountMinor: "30000", currencyCode: "CNY"),
             ResolvedDebt(from: ming, to: me, amountMinor: "80000", currencyCode: "THB"),
             ResolvedDebt(from: lin, to: ming, amountMinor: "900000", currencyCode: "CNY")]
func cards(_ g: WalkGroup, _ transfers: [ResolvedDebt] = debts, ready: Bool = true, filter: Set<String> = [], paletteCount: Int = 8) -> [WalletCurrency] {
    GroupWalletData.cards(group: g, participantID: "me", debts: transfers, suggestionReady: ready,
        paletteCount: paletteCount, currencyCodes: filter)
}
let all = cards(group)
precondition(all.map(\.id) == ["CNY", "THB", "SGD"])
let walletCodes = GroupWalletData.visibleCurrencyCodes(group: group, participantID: "me", currencyCodes: [])
precondition(walletCodes == all.map(\.id), "Statistics uses the same currency order as the wallet")
var position = WalletCardPosition()
precondition(position.frontCardID(in: walletCodes) == "CNY")
position.select("THB", available: walletCodes)
let savedPosition = WalletCardPosition.decode(position.encoded)
precondition(savedPosition.frontCardID(in: walletCodes) == "THB")
let remainingCodes = GroupWalletData.visibleCurrencyCodes(group: group, participantID: "me", currencyCodes: ["EUR", "SGD"])
precondition(remainingCodes == cards(group, filter: ["EUR", "SGD"]).map(\.id))
precondition(savedPosition.frontCardID(in: remainingCodes) == "SGD", "Use the visible front card when the saved currency is filtered out")
// FNV-1a("g") % 8 = 6. Color ranks follow CNY, SGD, THB,
// independently of the default-first card order CNY, THB, SGD.
precondition(all.map(\.artworkIndex) == [6, 0, 7], "Group hash sets the start; alphabetical currency ranks wrap the palette")
var reordered = group
reordered.currentUserCurrencyBalances.reverse()
reordered.currencyCode = "THB"
let originalColors = Dictionary(uniqueKeysWithValues: all.map { ($0.id, $0.artworkIndex) })
precondition(cards(reordered).allSatisfy { originalColors[$0.id] == $0.artworkIndex },
    "Server order and default currency must not alter colors")
var another = group
another.id = "hello"
precondition(cards(another).map(\.artworkIndex) == [3, 5, 4], "Stable group hash changes the palette start")
precondition(cards(group, paletteCount: 1).allSatisfy { $0.artworkIndex == 0 })
precondition(cards(group, paletteCount: 2).map(\.artworkIndex) == [0, 0, 1], "Respect a resized debug palette")
precondition(cards(group, paletteCount: 0).allSatisfy { $0.artworkIndex == 0 }, "Defensive empty count does not divide by zero")
var duplicate = group
duplicate.currentUserCurrencyBalances.append(projection("cny", cost: "120000"))
precondition(cards(duplicate).map(\.artworkIndex) == all.map(\.artworkIndex), "Normalized duplicate codes cannot shift colors")
precondition(all.map(\.expenseMinor) == ["120000", "680000", "24500"], "Use cost, never payments, debt, or a currency sum")
precondition(all[0].settlement.contains("Lin") && !all[0].settlement.contains("Ming"))
precondition(all[1].settlement.contains("Ming") && all[2].settlement == "Settled")
precondition(!all[0].isSettled && !all[1].isSettled && all[2].isSettled)
precondition(!cards(group, ready: false)[2].isSettled, "Do not mark settled while suggestions are loading")
let filtered = cards(group, filter: ["THB"])
precondition(filtered.count == 1 && filtered[0].expenseMinor == "680000" && filtered[0].artworkIndex == all[1].artworkIndex)
precondition(cards(group, filter: ["EUR"])[0].expenseMinor == "0")
precondition(cards(group, filter: ["AUD", "CAD", "CNY"]).map(\.artworkIndex) == [6, 7, 0],
    "Requested zero-balance currencies also receive consecutive alphabetical slots")
precondition(!cards(group, ready: false)[0].settlement.contains("Lin"), "No counterparty while suggestions are unavailable")
var settled = group
settled.currentUserCurrencyBalances[0].debtMinor = "0"
precondition(cards(settled, [])[0].expenseMinor == "120000", "Settlement never reduces personal spending")
precondition(cards(settled, [])[0].isSettled)
precondition(!cards(settled, [debts[0]])[0].isSettled, "Zero net balance with an outstanding transfer is not settled")
let mixed = cards(group, [debts[0], ResolvedDebt(from: ming, to: me, amountMinor: "10000", currencyCode: "CNY")])[0]
precondition(mixed.settlement.contains("Pay") && mixed.settlement.contains("receive"), "Do not net away opposing transfers")
var local = group
local.hasCurrentUserBalanceSummary = false
local.membersInfo[0].currencyBalances = group.currentUserCurrencyBalances
precondition(cards(local).map(\.expenseMinor) == all.map(\.expenseMinor), "Local participant projections match remote summaries")
var legacy = group
legacy.currentUserCurrencyBalances = []
precondition(cards(legacy)[0].expenseMinor == "120000")
legacy.hasCurrentUserBalanceSummary = false
precondition(cards(legacy)[0].expenseMinor == "777", "Legacy member cost fallback")
var zero = group
zero.currentUserCurrencyBalances = [projection("CNY", cost: "0", records: 0)]
precondition(cards(zero)[0].expenseMinor == "0", "Authoritative zero must not revive stale summary spending")
var advances = group
advances.currentUserCurrencyBalances = [projection("CNY", cost: "0", debt: "50000", paid: "50000")]
precondition(cards(advances)[0].expenseMinor == "0", "Paying for others does not become personal spending")
var partial = group
partial.membersInfo = []
precondition(cards(partial).map(\.expenseMinor) == all.map(\.expenseMinor), "Server summary works before members load")
partial.hasCurrentUserBalanceSummary = false
precondition(cards(partial).isEmpty, "Missing personal data is not invented zero spending")
print("PASS: personal cost vs payment/debt; multi-currency; local/remote/legacy; settlement directions; filters; zero/missing data")
'''
with tempfile.TemporaryDirectory(prefix='walkcalc-wallet-') as folder:
    path = Path(folder)
    (path / 'main.swift').write_text(source)
    subprocess.run(['xcrun', 'swiftc', str(path / 'main.swift'), '-o', str(path / 'verify')], check=True)
    subprocess.run([str(path / 'verify'), str(app / 'Resources/en.lproj/Localizable.strings')], check=True)
