#if DEBUG
import Foundation

enum BalancePresentationVerification {
    static func assertAllCasesPass() {
        verifyPersonalDebtFiltering()
        verifyStableDebtIdentity()
    }

    private static func verifyPersonalDebtFiltering() {
        let remoteMe = member(id: "remote-me", debt: "0")
        let localMe = member(id: "local-me", debt: "0")
        let alex = member(id: "alex", debt: "0")
        let sam = member(id: "sam", debt: "0")
        let debts = [
            ResolvedDebt(from: remoteMe, to: alex, amountMinor: "100"),
            ResolvedDebt(from: alex, to: remoteMe, amountMinor: "200"),
            ResolvedDebt(from: localMe, to: sam, amountMinor: "250"),
            ResolvedDebt(from: alex, to: sam, amountMinor: "300")
        ]
        let remotePersonal = BalancePresentation.personalDebts(debts, participantID: remoteMe.uuid)
        let localPersonal = BalancePresentation.personalDebts(debts, participantID: localMe.uuid)
        expect(remotePersonal.map(\.amountMinor), equals: ["100", "200"], prefix: "remote-personal-debt-filter")
        expect(localPersonal.map(\.amountMinor), equals: ["250"], prefix: "local-personal-debt-filter")
        expect(BalancePresentation.personalDebts(debts, participantID: nil).isEmpty, equals: true, prefix: "missing-participant")
    }

    private static func verifyStableDebtIdentity() {
        let alex = member(id: "alex", debt: "0")
        let yan = member(id: "yan", debt: "0")
        expect(
            ResolvedDebt(from: alex, to: yan, amountMinor: "300").id,
            equals: "alex->yan:300",
            prefix: "stable-debt-id"
        )
    }

    private static func member(id: String, debt: MoneyMinor) -> Member {
        Member(uuid: id, name: id, avatar: "", debtMinor: debt, costMinor: "0")
    }

    private static func expect<T: Equatable>(_ actual: T, equals expected: T, prefix: String) {
        assert(actual == expected, "\(prefix): expected '\(expected)', got '\(actual)'")
    }
}
#endif
