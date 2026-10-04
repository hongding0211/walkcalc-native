#if DEBUG
import Foundation

@MainActor
enum LocalLedgerUIFlowVerification {
    static func assertAllCasesPass() async {
        await verifyNoTokenBootstrapUsesLocalHome()
        await verifyStoreLocalOperations()
        await verifyMemberPaginationSurvivesNavigation()
        await verifySearchPaginationSurvivesNavigation()
        await verifyRecordFilters()
        await verifyStorePersistenceThroughSourceRecreation()
        await verifyRemoteOnlyOperationsAreGated()
        NSLog("PASS: local ledger UI flow verification")
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
        expect(store.recordsByGroup[groupId]?.isEmpty, equals: Optional(true), prefix: "local-ui-created-group-immediately-empty")
        expect(store.recordTotals[groupId], equals: Optional(0), prefix: "local-ui-created-group-empty-total")
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

    private static func verifyRecordFilters() async {
        let source = expectNoThrow({ try SwiftDataLedgerDataSource.inMemory() }, prefix: "filter-source")
        let repository = LedgerRepository(remoteSource: InMemoryLedgerDataSource(), localSource: source)
        let store = WalkcalcStore(ledgerRepository: repository, localOwnerId: "filter-owner")
        store.setPreferredLedgerSource(.local)
        expect(await store.createGroupWithFeedback(name: "Filter trip", users: [], tempUsers: ["Guest"], currencyCode: "USD").success, equals: true, prefix: "filter-create")
        let groupId = store.groups.first!.id
        let owner = store.localOwner
        let guest = store.groups.first!.tempUsers.first!.uuid
        let context = LedgerSessionContext.local(owner: owner)
        defer { UserDefaults.standard.removeObject(forKey: "walkcalc.recordFilters.\(owner.uuid).\(groupId)") }
        for index in 0..<25 {
            let result = await source.addRecord(groupId: groupId, who: index == 24 ? guest : owner.uuid,
                paidMinor: "100", forWhom: index == 24 ? [guest] : [owner.uuid, guest], type: "food", text: "Dinner \(index)",
                long: "", lat: "", occurredAt: 1_710_000_000_000 + Double(index), currencyCode: index < 12 ? "CNY" : "USD", context: context)
            guard case .success = result else { fail("filter-seed") }
        }
        let selection = GroupRecordFilters(currencyCodes: ["USD"], onlyRelatedToMe: true)
        store.setRecordFilters(selection, for: groupId)
        await store.refreshGroup(groupId)
        expect(store.records(groupId: groupId).count, equals: 10, prefix: "filter-first-page")
        await store.loadMoreRecords(groupId: groupId)
        expect(store.records(groupId: groupId).count, equals: 12, prefix: "filter-next-page")
        expect(store.records(groupId: groupId).allSatisfy { $0.currencyCode == "USD" && $0.who == owner.uuid }, equals: true, prefix: "filter-all-rows")
        expect(store.canLoadMoreRecords(groupId: groupId), equals: false, prefix: "filter-end")
        await store.searchRecords(groupId: groupId, query: "Dinner")
        expect(store.records(groupId: groupId, search: "Dinner").count, equals: 10, prefix: "filter-search-page")
        await store.loadMoreRecords(groupId: groupId, search: "Dinner")
        expect(store.records(groupId: groupId, search: "Dinner").count, equals: 12, prefix: "filter-search-end")
        await store.refreshSettlementSuggestion(groupId: groupId)
        let group = store.group(id: groupId)!
        expect(store.personalResolvedDebts(for: group).map(\.currencyCode), equals: ["USD"], prefix: "filter-suggestions")
        store.setRecordFilters(GroupRecordFilters(currencyCodes: ["USD"]), for: groupId)
        expect(store.personalResolvedDebts(for: group).map(\.currencyCode), equals: ["USD"], prefix: "filter-personal-switch-does-not-affect-suggestions")
        await store.refreshGroup(groupId)
        await store.loadMoreRecords(groupId: groupId)
        expect(store.records(groupId: groupId).count, equals: 13, prefix: "filter-includes-other-people")
        await store.refreshMemberRecords(groupId: groupId, memberId: guest)
        await store.loadMoreMemberRecords(groupId: groupId, memberId: guest)
        expect(store.memberRecordTotal(groupId: groupId, memberId: guest), equals: 13, prefix: "filter-member-total")
        expect(store.memberRecords(groupId: groupId, memberId: guest).allSatisfy { $0.currencyCode == "USD" }, equals: true, prefix: "filter-member-currency")
        let recreated = WalkcalcStore(ledgerRepository: repository, localOwnerId: owner.uuid)
        recreated.setPreferredLedgerSource(.local)
        _ = await recreated.refreshHome()
        expect(recreated.recordFilters(for: groupId), equals: GroupRecordFilters(currencyCodes: ["USD"]), prefix: "filter-persisted")
        let otherOwner = WalkcalcStore(ledgerRepository: repository, localOwnerId: "other-filter-owner")
        otherOwner.setPreferredLedgerSource(.local)
        expect(otherOwner.recordFilters(for: groupId).isActive, equals: false, prefix: "filter-owner-isolation")
        store.setRecordFilters(GroupRecordFilters(currencyCodes: ["EUR"]), for: groupId)
        await store.refreshGroup(groupId)
        expect(store.records(groupId: groupId).isEmpty, equals: true, prefix: "filter-empty")
        expect(store.personalResolvedDebts(for: group).isEmpty, equals: true, prefix: "filter-empty-suggestions")
        expect(store.filteredCurrencyBalances([], groupId: groupId), equals: [CurrencyBalanceSummary(currencyCode: "EUR", totalBalanceMinor: "0")], prefix: "filter-labeled-zero")
        store.setRecordFilters(GroupRecordFilters(currencyCodes: ["USD", "CNY"]), for: groupId)
        await store.refreshGroup(groupId)
        await store.loadMoreRecords(groupId: groupId)
        await store.loadMoreRecords(groupId: groupId)
        expect(store.records(groupId: groupId).count, equals: 25, prefix: "filter-multiple-currencies")
        store.setRecordFilters(GroupRecordFilters(), for: groupId)
        await store.refreshGroup(groupId)
        await store.loadMoreRecords(groupId: groupId)
        await store.loadMoreRecords(groupId: groupId)
        expect(store.records(groupId: groupId).count, equals: 25, prefix: "filter-clear")
        NSLog("PASS: record filters verification")
    }

    private static func verifyMemberPaginationSurvivesNavigation() async {
        let source = InMemoryLedgerDataSource()
        let store = WalkcalcStore(
            ledgerRepository: LedgerRepository(remoteSource: InMemoryLedgerDataSource(), localSource: source),
            localOwnerId: "member-pagination-owner"
        )
        store.setPreferredLedgerSource(.local)
        expect(await store.createGroupWithFeedback(name: "Pagination", users: [], tempUsers: []).success,
               equals: true, prefix: "member-pagination-create")
        let groupId = store.groups.first!.id
        let memberId = store.localOwner.uuid
        let context = LedgerSessionContext.local(owner: store.localOwner)
        for index in 0..<25 {
            let result = await source.addRecord(
                groupId: groupId, who: memberId, paidMinor: "100", forWhom: [memberId],
                type: "food", text: "Record \(index)", long: "", lat: "",
                occurredAt: 1_710_000_000_000 + Double(index), currencyCode: "USD", context: context
            )
            guard case .success = result else { fail("member-pagination-seed") }
        }

        await store.loadMemberRecordsIfNeeded(groupId: groupId, memberId: memberId)
        expect(store.memberRecords(groupId: groupId, memberId: memberId).count, equals: 10, prefix: "member-pagination-first-page")
        await store.loadMoreMemberRecords(groupId: groupId, memberId: memberId)
        let loadedRecords = store.memberRecords(groupId: groupId, memberId: memberId)
        expect(loadedRecords.count, equals: 20, prefix: "member-pagination-second-page")

        // SwiftUI reruns the screen task after returning from a record's detail.
        await store.loadMemberRecordsIfNeeded(groupId: groupId, memberId: memberId)
        expect(store.memberRecords(groupId: groupId, memberId: memberId), equals: loadedRecords, prefix: "member-pagination-return-preserves-records")
        expect(store.memberRecordTotal(groupId: groupId, memberId: memberId), equals: 25, prefix: "member-pagination-return-preserves-total")
        expect(store.canLoadMoreMemberRecords(groupId: groupId, memberId: memberId), equals: true, prefix: "member-pagination-return-can-continue")
        await store.loadMoreMemberRecords(groupId: groupId, memberId: memberId)
        let allRecords = store.memberRecords(groupId: groupId, memberId: memberId)
        expect(allRecords.count, equals: 25, prefix: "member-pagination-final-page")
        expect(Set(allRecords.map(\.recordId)).count, equals: 25, prefix: "member-pagination-no-duplicates")
        await store.loadMemberRecordsIfNeeded(groupId: groupId, memberId: memberId)
        expect(store.memberRecords(groupId: groupId, memberId: memberId), equals: allRecords, prefix: "member-pagination-return-at-end")
        expect(store.canLoadMoreMemberRecords(groupId: groupId, memberId: memberId), equals: false, prefix: "member-pagination-complete")

        // Explicit refreshes after a mutation must still replace stale records.
        await store.refreshMemberRecords(groupId: groupId, memberId: memberId)
        expect(store.memberRecords(groupId: groupId, memberId: memberId).count, equals: 10, prefix: "member-pagination-explicit-refresh")
        NSLog("PASS: member pagination survives navigation and continues through all 25 records")
    }

    private static func verifySearchPaginationSurvivesNavigation() async {
        let source = InMemoryLedgerDataSource()
        let store = WalkcalcStore(
            ledgerRepository: LedgerRepository(remoteSource: InMemoryLedgerDataSource(), localSource: source),
            localOwnerId: "search-pagination-owner"
        )
        store.setPreferredLedgerSource(.local)
        expect(await store.createGroupWithFeedback(name: "Search pagination", users: [], tempUsers: []).success,
               equals: true, prefix: "search-pagination-create")
        let groupId = store.groups.first!.id
        let memberId = store.localOwner.uuid
        let context = LedgerSessionContext.local(owner: store.localOwner)
        for index in 0..<25 {
            let result = await source.addRecord(
                groupId: groupId, who: memberId, paidMinor: "100", forWhom: [memberId],
                type: "food", text: "Dinner \(index)", long: "", lat: "",
                occurredAt: 1_710_000_000_000 + Double(index), currencyCode: "USD", context: context
            )
            guard case .success = result else { fail("search-pagination-seed") }
        }

        await store.searchRecordsIfNeeded(groupId: groupId, query: "Dinner")
        expect(store.records(groupId: groupId, search: "Dinner").count, equals: 10, prefix: "search-first-page")
        await store.loadMoreRecords(groupId: groupId, search: "Dinner")
        let loadedRecords = store.records(groupId: groupId, search: "Dinner")
        expect(loadedRecords.count, equals: 20, prefix: "search-second-page")

        // Reappearing tasks must not replace all loaded pages with page one.
        await store.searchRecordsIfNeeded(groupId: groupId, query: " Dinner ")
        expect(store.records(groupId: groupId, search: "Dinner"), equals: loadedRecords, prefix: "search-return-preserves-pages")
        expect(store.canLoadMoreRecords(groupId: groupId, search: "Dinner"), equals: true, prefix: "search-return-can-continue")
        await store.loadMoreRecords(groupId: groupId, search: "Dinner")
        await store.searchRecordsIfNeeded(groupId: groupId, query: "Dinner")
        let allRecords = store.records(groupId: groupId, search: "Dinner")
        expect(allRecords.count, equals: 25, prefix: "search-return-preserves-last-page")
        expect(Set(allRecords.map(\.recordId)).count, equals: 25, prefix: "search-no-duplicates")
        expect(store.canLoadMoreRecords(groupId: groupId, search: "Dinner"), equals: false, prefix: "search-complete")

        await store.searchRecordsIfNeeded(groupId: groupId, query: "No match")
        expect(store.hasLoadedSearchRecords(groupId: groupId, search: "No match"), equals: true, prefix: "search-empty-cached")
        expect(store.records(groupId: groupId, search: "No match").isEmpty, equals: true, prefix: "search-new-query")

        // Refreshing after a ledger mutation invalidates the search cache.
        await store.refreshGroup(groupId)
        expect(store.hasLoadedSearchRecords(groupId: groupId, search: "Dinner"), equals: false, prefix: "search-refresh-invalidates")
        await store.searchRecordsIfNeeded(groupId: groupId, query: "Dinner")
        expect(store.records(groupId: groupId, search: "Dinner").count, equals: 10, prefix: "search-refresh-reloads")
        NSLog("PASS: search pagination survives navigation and reloads after invalidation")
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
