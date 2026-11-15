import Foundation

struct WalletCurrency: Identifiable {
    let id: String
    let expenseMinor: MoneyMinor
    let balanceMinor: MoneyMinor
    let settlement: String
    let artworkIndex: Int
    var isSettled: Bool = false

    var name: String { CurrencyCatalog.currencyInfo(for: id).name }
    var spending: String { CurrencyCatalog.formatted(expenseMinor, currencyCode: id, style: .exact) }
}

// Uses whole-ledger personal projections, never the currently loaded record page.
enum GroupWalletData {
    static func cards(group: WalkGroup, participantID: String?, debts: [ResolvedDebt],
                      suggestionReady: Bool, currencyCodes: Set<String> = []) -> [WalletCurrency] {
        let member = group.allMembers.first { $0.uuid == participantID }
        guard group.hasCurrentUserBalanceSummary || member != nil else { return [] }
        let defaultCode = CurrencyCatalog.normalizedCode(group.currencyCode)
        let projections = group.hasCurrentUserBalanceSummary
            ? group.currentUserCurrencyBalances : member?.currencyBalances ?? []
        var balances: [MemberCurrencyProjection]
        if projections.isEmpty {
            balances = [MemberCurrencyProjection(
                currencyCode: defaultCode,
                debtMinor: group.hasCurrentUserBalanceSummary ? group.currentUserBalanceMinor : member?.debtMinor ?? "0",
                costMinor: group.hasCurrentUserBalanceSummary ? group.currentUserExpenseShareMinor : member?.costMinor ?? "0",
                paidTotalMinor: "0", recordCount: 0, settlementInMinor: "0", settlementOutMinor: "0")]
        } else {
            balances = projections.filter(\.hasLedgerActivity)
        }
        if balances.isEmpty {
            balances = [zero(defaultCode)]
        }
        // Preserve server order, but keep the default currency first when it has activity.
        balances = balances.filter { CurrencyCatalog.normalizedCode($0.currencyCode) == defaultCode }
            + balances.filter { CurrencyCatalog.normalizedCode($0.currencyCode) != defaultCode }
        let selectedCodes = Set(currencyCodes.map(CurrencyCatalog.normalizedCode))
        let visible = selectedCodes.isEmpty ? balances : selectedCodes.sorted().map { code in
            balances.first { CurrencyCatalog.normalizedCode($0.currencyCode) == code } ?? zero(code)
        }
        let personal = BalancePresentation.personalDebts(debts, participantID: participantID)
        var seen = Set<String>()
        return visible.compactMap { projection in
            let code = CurrencyCatalog.normalizedCode(projection.currencyCode)
            guard seen.insert(code).inserted else { return nil }
            let transfers = personal.filter { CurrencyCatalog.normalizedCode($0.currencyCode) == code }
            let ready = suggestionReady || !group.hasUnresolvedBalance
            return WalletCurrency(
                id: code, expenseMinor: projection.costMinor, balanceMinor: projection.debtMinor,
                settlement: settlementText(transfers, participantID: participantID, projection: projection,
                    ready: ready),
                artworkIndex: balances.firstIndex { CurrencyCatalog.normalizedCode($0.currencyCode) == code } ?? balances.count,
                isSettled: ready && Money.isZero(projection.debtMinor) && transfers.isEmpty)
        }
    }

    private static func zero(_ code: String) -> MemberCurrencyProjection {
        MemberCurrencyProjection(currencyCode: code, debtMinor: "0", costMinor: "0", paidTotalMinor: "0",
                                 recordCount: 0, settlementInMinor: "0", settlementOutMinor: "0")
    }

    private static func settlementText(_ debts: [ResolvedDebt], participantID: String?,
                                       projection: MemberCurrencyProjection, ready: Bool) -> String {
        func amount(_ minor: MoneyMinor) -> String {
            CurrencyCatalog.formatted(minor, currencyCode: projection.currencyCode, style: .exact)
        }
        // Show counterparties only after suggestions are available.
        let outgoing = ready ? debts.filter { $0.from.uuid == participantID } : []
        let incoming = ready ? debts.filter { $0.to.uuid == participantID } : []
        let toPay = outgoing.reduce("0") { Money.add($0, $1.amountMinor) }
        let toReceive = incoming.reduce("0") { Money.add($0, $1.amountMinor) }
        if !outgoing.isEmpty && !incoming.isEmpty {
            return String(format: L("Wallet.payAndReceive"), amount(toPay), amount(toReceive))
        }
        if !outgoing.isEmpty {
            return String(format: L("You need to pay %@ %@"), names(outgoing.map(\.to)), amount(toPay))
        }
        if !incoming.isEmpty {
            return String(format: L("%@ needs to pay you %@"), names(incoming.map(\.from)), amount(toReceive))
        }
        if Money.isNegative(projection.debtMinor) {
            return String(format: L("Wallet.toPay"), amount(Money.absolute(projection.debtMinor)))
        }
        if Money.isPositive(projection.debtMinor) {
            return String(format: L("Wallet.toReceive"), amount(projection.debtMinor))
        }
        return ready ? L("Settled") : L("Wallet.loadingSettlement")
    }

    private static func names(_ members: [Member]) -> String {
        var seen = Set<String>()
        let unique = members.filter { seen.insert($0.uuid).inserted }
        if unique.count > 2 {
            return String(format: L("Record.recipient group"), unique[0].name, String(unique.count))
        }
        return unique.map(\.name).joined(separator: L("Record.pair separator"))
    }
}
