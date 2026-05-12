#if DEBUG
import Foundation

@MainActor
enum LedgerMigrationVerification {
    static func assertAllCasesPass() {
        let store = WalkcalcStore()
        let group = WalkGroup(
            id: "verify-ledger",
            name: "Verify Ledger",
            createdAt: 0,
            modifiedAt: 0,
            membersInfo: [
                Member(uuid: "payer-a", name: "A", avatar: "", debtMinor: "6666", costMinor: "3334", recordCount: 1),
                Member(uuid: "payer-b", name: "B", avatar: "", debtMinor: "-3333", costMinor: "3333", recordCount: 1),
                Member(uuid: "temp-c", name: "C", avatar: "", debtMinor: "-3333", costMinor: "3333", recordCount: 1, isTemporary: true)
            ],
            tempUsers: [],
            archivedUsers: [],
            isOwner: true
        )

        let debts = store.resolvedDebts(for: group)
        expect(debts.count, equals: 2, prefix: "settlement-count")
        expect(debts.reduce("0") { Money.add($0, $1.amountMinor) }, equals: "6666", prefix: "settlement-total")
        expect(debts.allSatisfy { $0.to.uuid == "payer-a" }, equals: true, prefix: "settlement-receiver")
        expect(Set(debts.map(\.from.uuid)), equals: Set(["payer-b", "temp-c"]), prefix: "settlement-payers")
        expect(Set(debts.map(\.amountMinor)), equals: Set(["3333"]), prefix: "settlement-amounts")
    }

    private static func expect<T: Equatable>(_ actual: T, equals expected: T, prefix: String) {
        assert(actual == expected, "\(prefix): expected '\(expected)', got '\(actual)'")
    }
}
#endif
