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
    static func personalCurrencyProjections(group: WalkGroup, participantID: String?) -> [MemberCurrencyProjection] {
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
        return balances.filter { CurrencyCatalog.normalizedCode($0.currencyCode) == defaultCode }
            + balances.filter { CurrencyCatalog.normalizedCode($0.currencyCode) != defaultCode }
    }

    static func visibleCurrencyCodes(group: WalkGroup, participantID: String?, currencyCodes: Set<String>) -> [String] {
        let balances = personalCurrencyProjections(group: group, participantID: participantID)
        let selectedCodes = Set(currencyCodes.map { CurrencyCatalog.normalizedCode($0) })
        return visibleCurrencyCodes(in: balances, selectedCodes: selectedCodes)
    }

    private static func visibleCurrencyCodes(in balances: [MemberCurrencyProjection], selectedCodes: Set<String>) -> [String] {
        guard !balances.isEmpty else { return [] }
        if !selectedCodes.isEmpty { return selectedCodes.sorted() }
        var seen = Set<String>()
        return balances.map { CurrencyCatalog.normalizedCode($0.currencyCode) }.filter { seen.insert($0).inserted }
    }

    static func cards(group: WalkGroup, participantID: String?, debts: [ResolvedDebt],
                      suggestionReady: Bool, paletteCount: Int,
                      currencyCodes: Set<String> = []) -> [WalletCurrency] {
        let balances = personalCurrencyProjections(group: group, participantID: participantID)
        guard !balances.isEmpty else { return [] }
        let selectedCodes = Set(currencyCodes.map { CurrencyCatalog.normalizedCode($0) })
        // Rank the full set before filtering, including requested zero-balance
        // currencies. Server/default/stack order never determines card colors.
        let colorCodes = Set(balances.map { CurrencyCatalog.normalizedCode($0.currencyCode) })
            .union(selectedCodes).sorted()
        let colorCount = max(1, paletteCount)
        let colorStart = paletteStart(groupID: group.id, count: colorCount)
        let visibleCodes = visibleCurrencyCodes(in: balances, selectedCodes: selectedCodes)
        let balancesByCode = Dictionary(balances.map { (CurrencyCatalog.normalizedCode($0.currencyCode), $0) },
                                        uniquingKeysWith: { first, _ in first })
        let personal = BalancePresentation.personalDebts(debts, participantID: participantID)
        return visibleCodes.map { code in
            let projection = balancesByCode[code] ?? zero(code)
            let transfers = personal.filter { CurrencyCatalog.normalizedCode($0.currencyCode) == code }
            let ready = suggestionReady || !group.hasUnresolvedBalance
            let relativeIndex = colorCodes.prefix { $0 < code }.count
            return WalletCurrency(
                id: code, expenseMinor: projection.costMinor, balanceMinor: projection.debtMinor,
                settlement: settlementText(transfers, participantID: participantID, projection: projection,
                    ready: ready),
                artworkIndex: (colorStart + relativeIndex) % colorCount,
                isSettled: ready && Money.isZero(projection.debtMinor) && transfers.isEmpty)
        }
    }

    static func paletteStart(groupID: String, count: Int) -> Int {
        // FNV-1a over UTF-8 is stable across launches and devices. Swift's
        // Hasher/hashValue is randomly seeded and cannot persist this mapping.
        let hash = groupID.utf8.reduce(UInt64(14_695_981_039_346_656_037)) {
            ($0 ^ UInt64($1)) &* 1_099_511_628_211
        }
        return Int(hash % UInt64(count))
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
