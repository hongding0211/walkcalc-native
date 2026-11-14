#!/usr/bin/env python3
"""Run the real group-row balance selector against multi-currency regressions."""
from pathlib import Path
import subprocess
import tempfile

root = Path(__file__).resolve().parents[1]
home = (root / "walkcalc-native/Features/Home/HomeViews.swift").read_text()
start = home.index("    private var carouselBalances:")
selectors = home[start:home.index("    private var accessibilityBalanceText:", start)]
selectors = selectors.replace("private var", "var")
models = (root / "walkcalc-native/Core/Models/Models.swift").read_text()
members = models[models.index("struct Member:"):models.index("struct GroupPinState")]
ledger = (root / "walkcalc-native/Core/Ledger/LedgerDataLayer.swift").read_text()
summary = ledger[ledger.index("struct CurrencyBalanceSummary:"):ledger.index("struct HomeBalanceSummary:")]
ui = (root / "walkcalc-native/Shared/UI/SoftLedgerUI.swift").read_text()
style = ui[ui.index("enum MoneyDisplayStyle {"):ui.index("func signedMoney(")]
source = "\n".join([
    (root / "walkcalc-native/Shared/Localization/L10n.swift").read_text(),
    (root / "walkcalc-native/Core/Models/Money.swift").read_text(),
    style, members, summary,
]) + r'''
struct Group {
    var hasCurrentUserBalanceSummary: Bool
    var currentUserCurrencyBalances: [MemberCurrencyProjection]
    var currentUserRecordCount: Int = 0
    var currentUserExpenseShareMinor: MoneyMinor = "0"
    var currentUserPaidTotalMinor: MoneyMinor = "0"
    var currencyCode: String = "THB"
}
struct Row {
    var group: Group
    var currentMember: Member?
    var myBalance: MoneyMinor
SELECTORS
}
func check(_ balances: [(String, String)], legacy: String, activity: Bool = true,
           expected: [String], status: String? = nil, _ name: String) {
    let projections = balances.map {
        MemberCurrencyProjection(currencyCode: $0.0, debtMinor: $0.1,
            costMinor: activity ? "100" : "0", paidTotalMinor: "0",
            recordCount: activity ? 1 : 0, settlementInMinor: "0", settlementOutMinor: "0")
    }
    // Exercise both the API summary and the current-member/local-ledger path.
    for remote in [true, false] {
        let member = Member(uuid: "me", name: "Me", avatar: "", debtMinor: legacy,
            costMinor: activity ? "100" : "0", recordCount: activity ? 1 : 0,
            currencyBalances: remote ? [] : projections)
        let row = Row(group: Group(hasCurrentUserBalanceSummary: remote,
            currentUserCurrencyBalances: remote ? projections : [],
            currentUserRecordCount: activity ? 1 : 0), currentMember: member, myBalance: legacy)
        let visible = row.carouselBalances
        precondition(visible.map { $0.currencyCode } == expected, name)
        precondition(visible.allSatisfy { !Money.isZero($0.totalBalanceMinor) }, name)
        if let status {
            precondition(visible.isEmpty && row.zeroBalanceText == status, name)
        }
    }
}
check([("THB", "0"), ("USD", "123")], legacy: "0", expected: ["USD"], "Only outstanding USD remains")
check([("THB", "0"), ("USD", "-123")], legacy: "0", expected: ["USD"], "Negative debt remains")
check([("THB", "0"), ("USD", "0")], legacy: "999", expected: [], status: "Settled", "All settled; ignore stale legacy")
check([("THB", "-0"), ("USD", "0")], legacy: "0", expected: [], status: "Settled", "Zero variants never create pages")
check([("USD", "100"), ("THB", "-100")], legacy: "0", expected: ["THB", "USD"], "Different currencies cannot cancel")
check([("USD", "1"), ("THB", "-1")], legacy: "0", activity: false, expected: ["THB", "USD"], "One minor unit counts without history")
check([], legacy: "0", activity: false, expected: [], status: "No activity", "Empty ledger")
check([], legacy: "0", expected: [], status: "Settled", "Settled legacy ledger")
check([], legacy: "100", expected: ["THB"], "Legacy fallback only when projections are absent")
print("PASS: 18 remote/local cases; zero, one and multiple outstanding currencies; settled/no-activity; legacy fallback")
'''.replace("SELECTORS", selectors)

with tempfile.TemporaryDirectory(prefix="walkcalc-group-row-balances-") as directory:
    file = Path(directory) / "main.swift"
    file.write_text(source)
    executable = Path(directory) / "verify"
    subprocess.run(["xcrun", "swiftc", str(file), "-o", str(executable)], check=True)
    subprocess.run([str(executable)], check=True)
