#!/usr/bin/env python3
"""Exercise the real home summary selector with API/local-ledger balance cases."""
from pathlib import Path
import subprocess
import tempfile

root = Path(__file__).resolve().parents[1]
home = (root / 'walkcalc-native/Features/Home/HomeViews.swift').read_text()
start = home.index('    private var balances:', home.index('private struct HomeBalanceCard: View'))
selector = home[start:home.index('    private func scopeCount(', start)].replace('private var', 'var', 1)
ledger = (root / 'walkcalc-native/Core/Ledger/LedgerDataLayer.swift').read_text()
summary = ledger[ledger.index('struct CurrencyBalanceSummary:'):ledger.index('struct HomeBalanceSummary:')]
ui = (root / 'walkcalc-native/Shared/UI/SoftLedgerUI.swift').read_text()
style = ui[ui.index('enum MoneyDisplayStyle {'):ui.index('func signedMoney(')]
source = (root / 'walkcalc-native/Shared/Localization/L10n.swift').read_text() + '\n' + (root / 'walkcalc-native/Core/Models/Money.swift').read_text() + '\n' + style + '\n' + summary + '''
struct Store {
    var totalBalancesByCurrency: [CurrencyBalanceSummary]
    var totalBalanceMinor: MoneyMinor
}
struct Home {
    var store: Store
SELECTOR
}
func check(_ rows: [(String, String)], legacy: String, expected: [String], _ name: String) {
    let store = Store(totalBalancesByCurrency: rows.map {
        CurrencyBalanceSummary(currencyCode: $0.0, totalBalanceMinor: $0.1)
    }, totalBalanceMinor: legacy)
    let visible = Home(store: store).balances
    precondition(visible.map(\\.currencyCode) == expected, name)
    precondition(visible.allSatisfy { !Money.isZero($0.totalBalanceMinor) }, name)
}
check([("THB", "0"), ("USD", "123")], legacy: "123", expected: ["USD"], "settled THB is hidden")
check([("THB", "-0"), ("USD", "0")], legacy: "999", expected: [], "zero currency summaries must not revive a stale legacy total")
check([("USD", "100"), ("THB", "-100")], legacy: "0", expected: ["THB", "USD"], "different currencies cannot cancel each other")
check([("USD", "1"), ("THB", "-1")], legacy: "0", expected: ["THB", "USD"], "one minor unit remains visible")
check([], legacy: "0", expected: [], "empty and fully settled home")
check([], legacy: "100", expected: [CurrencyCatalog.defaultCurrencyCode()], "legacy API fallback")
print("PASS: settled currencies hidden; nonzero debit/credit and minor units preserved; authoritative summaries and legacy fallback")
'''.replace('SELECTOR', selector)
with tempfile.TemporaryDirectory(prefix='walkcalc-home-balance-') as directory:
    file = Path(directory) / 'main.swift'
    file.write_text(source)
    executable = Path(directory) / 'verify'
    subprocess.run(['xcrun', 'swiftc', str(file), '-o', str(executable)], check=True)
    subprocess.run([str(executable)], check=True)
