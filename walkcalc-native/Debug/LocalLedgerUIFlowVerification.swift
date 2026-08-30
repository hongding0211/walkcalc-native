#if DEBUG
import Foundation

@MainActor
enum LocalLedgerUIFlowVerification {
    static func assertAllCasesPass() async {
        await verifyNoTokenBootstrapUsesLocalHome()
        await verifyStoreLocalOperations()
        await verifyStorePersistenceThroughSourceRecreation()
        await verifyRemoteOnlyOperationsAreGated()
    }

    private static func verifyNoTokenBootstrapUsesLocalHome() async {
        let previousToken = UserDefaults.standard.string(forKey: "walkcalc.token")
        UserDefaults.standard.removeObject(forKey: "walkcalc.token")
        defer {
            if let previousToken {
                UserDefaults.standard.set(previousToken, forKey: "walkcalc.token")
            } else {
                UserDefaults.standard.removeObject(forKey: "walkcalc.token")
            }
        }

        let source = expectNoThrow({ try SwiftDataLedgerDataSource.inMemory() }, prefix: "local-ui-bootstrap-source")
        let store = WalkcalcStore(
            ledgerRepository: LedgerRepository(remoteSource: InMemoryLedgerDataSource(), localSource: source),
            localOwnerId: "local-ui-bootstrap-owner"
        )

        await store.bootstrap()

        expect(store.startupRoute, equals: .authenticated, prefix: "local-ui-bootstrap-route")
        expect(store.preferredLedgerSource, equals: .local, prefix: "local-ui-bootstrap-source-kind")
        expect(store.groups.isEmpty, equals: true, prefix: "local-ui-bootstrap-empty-home")
    }

    private static func verifyStoreLocalOperations() async {
        let source = expectNoThrow({ try SwiftDataLedgerDataSource.inMemory() }, prefix: "local-ui-source")
        let store = WalkcalcStore(
            ledgerRepository: LedgerRepository(remoteSource: InMemoryLedgerDataSource(), localSource: source),
            localOwnerId: "local-ui-owner"
        )
        store.setPreferredLedgerSource(.local)

        expect(
            await store.createGroupWithFeedback(
                name: "Local UI Trip",
                users: [],
                tempUsers: ["Guest"],
                currencyCode: "USD"
            ).success,
            equals: true,
            prefix: "local-ui-create"
        )
        expect(store.groups.count, equals: 1, prefix: "local-ui-home-count")
        let groupId = store.groups.first?.id ?? ""
        let preferenceKey = "walkcalc.recordCurrency.\(groupId)"
        UserDefaults.standard.removeObject(forKey: preferenceKey)
        defer { UserDefaults.standard.removeObject(forKey: preferenceKey) }
        expect(groupId.hasPrefix("l-"), equals: true, prefix: "local-ui-group-id")
        expect(store.groups.first?.currencyCode, equals: Optional("USD"), prefix: "local-ui-group-currency")
        expect(store.preferredRecordCurrencyCode(for: groupId), equals: "USD", prefix: "local-ui-record-currency-default")
        store.rememberRecordCurrencyCode("CNY", for: groupId)
        store.groups[0].currencyCode = "EUR"
        expect(store.preferredRecordCurrencyCode(for: groupId), equals: "CNY", prefix: "local-ui-record-currency-cache")
        store.groups[0].currencyCode = "USD"
        expect(store.sourceMetadata(for: groupId)?.source, equals: Optional(.local), prefix: "local-ui-source-metadata")

        await store.refreshGroup(groupId)
        let group = store.group(id: groupId)
        let ownerId = store.localOwner.uuid
        let guestId = group?.tempUsers.first?.uuid ?? ""
        expect(group?.allMembers.count, equals: Optional(2), prefix: "local-ui-detail-members")

        expect(await store.addMembersWithFeedback(groupId: groupId, users: [], tempUsers: ["Second Guest"]).success, equals: true, prefix: "local-ui-add-temp")
        await store.refreshGroup(groupId)
        expect(store.group(id: groupId)?.tempUsers.count, equals: Optional(2), prefix: "local-ui-temp-count")

        expect(await store.addRecordWithFeedback(groupId: groupId, who: ownerId, paid: "12.00", forWhom: [ownerId, guestId], type: "food", text: "Dinner", occurredAt: 1_710_000_000_000, currencyCode: "EUR").success, equals: true, prefix: "local-ui-add-record")
        expect(store.records(groupId: groupId).count, equals: 1, prefix: "local-ui-record-count")
        expect(store.records(groupId: groupId).first?.currencyCode, equals: Optional("EUR"), prefix: "local-ui-created-record-currency")
        let recordId = store.records(groupId: groupId).first?.recordId ?? ""

        expect(await store.editRecordWithFeedback(groupId: groupId, recordId: recordId, who: ownerId, paid: "15.00", forWhom: [ownerId, guestId], type: "food", text: "Dinner updated", occurredAt: 1_710_000_000_001, currencyCode: "CNY").success, equals: true, prefix: "local-ui-edit-record")
        expect(store.records(groupId: groupId).first?.currencyCode, equals: Optional("CNY"), prefix: "local-ui-edited-record-currency")
        await store.searchRecords(groupId: groupId, query: "updated")
        expect(store.records(groupId: groupId, search: "updated").count, equals: 1, prefix: "local-ui-search")

        expect(await store.addRecordWithFeedback(groupId: groupId, who: ownerId, paid: "40.00", forWhom: [ownerId, guestId], type: "shopping", text: "USD purchase", occurredAt: 1_710_000_000_002, currencyCode: "USD").success, equals: true, prefix: "local-ui-add-usd-record")

        await store.refreshSettlementSuggestion(groupId: groupId)
        let settlementDebts = store.resolvedDebts(for: store.group(id: groupId) ?? group!)
        expect(settlementDebts.isEmpty, equals: false, prefix: "local-ui-settlement")
        expect(settlementDebts.map(\.currencyCode), equals: ["USD", "CNY"], prefix: "local-ui-settlement-currency-order")
        expect(settlementDebts.map(\.amountMinor), equals: ["2000", "750"], prefix: "local-ui-settlement-absolute-order")
        expect(await store.resolveAllWithFeedback(groupId: groupId, debts: settlementDebts).success, equals: true, prefix: "local-ui-resolve")

        expect(await store.deleteRecordWithFeedback(groupId: groupId, recordId: recordId).success, equals: true, prefix: "local-ui-delete-record")
        expect(store.records(groupId: groupId).contains(where: { $0.recordId == recordId }), equals: false, prefix: "local-ui-record-deleted")

        expect(await store.changeGroupNameWithFeedback(groupId, name: "Renamed Local UI Trip").success, equals: true, prefix: "local-ui-rename")
        expect(store.group(id: groupId)?.name, equals: Optional("Renamed Local UI Trip"), prefix: "local-ui-renamed")
        expect(await store.archiveGroupWithFeedback(groupId).success, equals: true, prefix: "local-ui-archive")
        expect(await store.unarchiveGroupWithFeedback(groupId).success, equals: true, prefix: "local-ui-unarchive")
        expect(await store.deleteGroupWithFeedback(groupId).success, equals: true, prefix: "local-ui-delete-group")
        expect(store.groups.isEmpty, equals: true, prefix: "local-ui-group-deleted")
    }

    private static func verifyStorePersistenceThroughSourceRecreation() async {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("walkcalc-local-ui-flow-\(UUID().uuidString)", isDirectory: true)
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let storeURL = directory.appendingPathComponent("LocalLedger.store")
        let ownerId = "local-ui-persist-owner"

        do {
            let source = try SwiftDataLedgerDataSource.temporaryPersistentStore(url: storeURL)
            let store = WalkcalcStore(
                ledgerRepository: LedgerRepository(remoteSource: InMemoryLedgerDataSource(), localSource: source),
                localOwnerId: ownerId
            )
            store.setPreferredLedgerSource(.local)
            _ = await store.createGroupWithFeedback(name: "Persisted UI Trip", users: [], tempUsers: ["Guest"])
        } catch {
            fail("local-ui-persist-first threw \(error)")
        }

        do {
            let source = try SwiftDataLedgerDataSource.temporaryPersistentStore(url: storeURL)
            let store = WalkcalcStore(
                ledgerRepository: LedgerRepository(remoteSource: InMemoryLedgerDataSource(), localSource: source),
                localOwnerId: ownerId
            )
            store.setPreferredLedgerSource(.local)
            expect(await store.refreshHome(search: "Persisted"), equals: true, prefix: "local-ui-persist-refresh")
            expect(store.groups.first?.name, equals: Optional("Persisted UI Trip"), prefix: "local-ui-persist-name")
        } catch {
            fail("local-ui-persist-second threw \(error)")
        }
    }

    private static func verifyRemoteOnlyOperationsAreGated() async {
        let source = expectNoThrow({ try SwiftDataLedgerDataSource.inMemory() }, prefix: "local-ui-gate-source")
        let store = WalkcalcStore(
            ledgerRepository: LedgerRepository(remoteSource: InMemoryLedgerDataSource(), localSource: source),
            localOwnerId: "local-ui-gate-owner"
        )
        store.setPreferredLedgerSource(.local)
        expect(await store.createGroupWithFeedback(name: "Gated Local Trip", users: [], tempUsers: []).success, equals: true, prefix: "local-ui-gate-create")
        let groupId = store.groups.first?.id ?? ""
        let beforeGroups = store.groups

        let join = await store.joinGroupWithFeedback(code: "ABCD")
        expect(join.success, equals: false, prefix: "local-ui-join-auth")
        let searchUsers = await store.searchUsers(name: "Wei")
        expect(searchUsers.isEmpty, equals: true, prefix: "local-ui-search-users-auth")
        expect(await store.addMembersWithFeedback(groupId: groupId, users: [UserProfile(uuid: "remote-user", name: "Remote User", avatar: "")], tempUsers: []).success, equals: false, prefix: "local-ui-invite-auth")
        expect(store.groups, equals: beforeGroups, prefix: "local-ui-gated-state-unchanged")
    }

    private static func expectNoThrow<Value>(_ work: () throws -> Value, prefix: String) -> Value {
        do {
            return try work()
        } catch {
            fatalError("Verification failed [\(prefix)]: threw \(error)")
        }
    }

    private static func expect<T: Equatable>(_ actual: T, equals expected: T, prefix: String) {
        guard actual == expected else {
            fatalError("Verification failed [\(prefix)]: expected \(expected), got \(actual)")
        }
    }

    private static func fail(_ message: String) -> Never {
        fatalError("Verification failed: \(message)")
    }
}
#endif
