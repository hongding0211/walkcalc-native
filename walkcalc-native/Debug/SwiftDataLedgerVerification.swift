#if DEBUG
import Foundation

@MainActor
enum SwiftDataLedgerVerification {
    static func assertAllCasesPass() async {
        await verifyInMemoryLocalOperations()
        await verifyPersistentStoreSurvivesRecreation()
    }

    private static func verifyInMemoryLocalOperations() async {
        let source = expectNoThrow({ try SwiftDataLedgerDataSource.inMemory() }, prefix: "swiftdata-in-memory-source")
        let owner = Member(uuid: "local-owner", name: "Me", avatar: "", debtMinor: "0", costMinor: "0")
        let repository = LedgerRepository(remoteSource: InMemoryLedgerDataSource(), localSource: source)
        let context = LedgerSessionContext.local(owner: owner)

        let groupId = expectSuccess(await repository.createGroup(name: "Local Trip", context: context), prefix: "swiftdata-create-group").value ?? ""
        expect(groupId.hasPrefix("local-group-"), equals: true, prefix: "swiftdata-group-id-prefix")

        let guestId = expectSuccess(await repository.addTempUser(code: groupId, name: "Guest", context: context), prefix: "swiftdata-add-temp").value ?? ""
        expect(guestId.hasPrefix("local-member-"), equals: true, prefix: "swiftdata-temp-id-prefix")

        let home = expectSuccess(await repository.home(page: 1, pageSize: 1, search: "trip", context: context), prefix: "swiftdata-home")
        expect(home.groups.count, equals: 1, prefix: "swiftdata-home-search-count")
        expect(home.groupPagination?.total, equals: Optional(1), prefix: "swiftdata-home-total")

        let record = expectSuccess(await repository.addRecord(
            groupId: groupId,
            who: owner.uuid,
            paidMinor: "1200",
            forWhom: [owner.uuid, guestId],
            type: "food",
            text: "Dinner",
            long: "",
            lat: "",
            occurredAt: 1_710_000_000_000,
            context: context
        ), prefix: "swiftdata-add-record").value
        expect(record?.text, equals: Optional("Dinner"), prefix: "swiftdata-record-note")

        let balances = expectSuccess(await repository.groupBalances(groupId: groupId, context: context), prefix: "swiftdata-balances").value ?? []
        expect(balances.first(where: { $0.uuid == owner.uuid })?.debtMinor, equals: Optional("600"), prefix: "swiftdata-owner-balance")
        expect(balances.first(where: { $0.uuid == guestId })?.debtMinor, equals: Optional("-600"), prefix: "swiftdata-guest-balance")

        let search = expectSuccess(await repository.records(groupId: groupId, page: 1, pageSize: 10, search: .noteOrCategoryName(query: "Dinner"), context: context), prefix: "swiftdata-note-search")
        expect(search.items.count, equals: 1, prefix: "swiftdata-note-search-count")

        let categorySearch = expectSuccess(await repository.records(groupId: groupId, page: 1, pageSize: 10, search: .noteOrCategoryName(query: L(expenseCategory(for: "food").titleKey)), context: context), prefix: "swiftdata-category-search")
        expect(categorySearch.items.count, equals: 1, prefix: "swiftdata-category-search-count")

        let memberRecords = expectSuccess(await repository.memberRecords(groupId: groupId, memberId: guestId, page: 1, pageSize: 10, context: context), prefix: "swiftdata-member-records")
        expect(memberRecords.records.count, equals: 1, prefix: "swiftdata-member-record-count")

        let settlement = expectSuccess(await repository.settlementSuggestion(groupId: groupId, context: context), prefix: "swiftdata-settlement-suggestion").value ?? []
        expect(settlement.first?.fromId, equals: Optional(guestId), prefix: "swiftdata-settlement-from")
        expect(settlement.first?.toId, equals: Optional(owner.uuid), prefix: "swiftdata-settlement-to")
        expect(settlement.first?.amountMinor, equals: Optional("600"), prefix: "swiftdata-settlement-amount")

        let edited = expectSuccess(await repository.updateRecord(
            groupId: groupId,
            recordId: record?.recordId ?? "",
            who: owner.uuid,
            paidMinor: "1500",
            forWhom: [owner.uuid, guestId],
            type: "food",
            text: "Dinner updated",
            occurredAt: 1_710_000_000_001,
            isSettlement: false,
            context: context
        ), prefix: "swiftdata-edit-record").value
        expect(edited?.paidMinor, equals: Optional("1500"), prefix: "swiftdata-edited-amount")

        let editedBalances = expectSuccess(await repository.groupBalances(groupId: groupId, context: context), prefix: "swiftdata-edited-balances").value ?? []
        expect(editedBalances.first(where: { $0.uuid == owner.uuid })?.debtMinor, equals: Optional("750"), prefix: "swiftdata-edited-owner-balance")
        expect(editedBalances.first(where: { $0.uuid == guestId })?.debtMinor, equals: Optional("-750"), prefix: "swiftdata-edited-guest-balance")

        let resolve = expectSuccess(await repository.resolveDebts(groupId: groupId, context: context), prefix: "swiftdata-resolve").value ?? []
        expect(resolve.count, equals: 1, prefix: "swiftdata-resolve-record-count")

        let resolvedBalances = expectSuccess(await repository.groupBalances(groupId: groupId, context: context), prefix: "swiftdata-resolved-balances").value ?? []
        expect(resolvedBalances.first(where: { $0.uuid == owner.uuid })?.debtMinor, equals: Optional("0"), prefix: "swiftdata-resolved-owner-balance")
        expect(resolvedBalances.first(where: { $0.uuid == guestId })?.debtMinor, equals: Optional("0"), prefix: "swiftdata-resolved-guest-balance")

        _ = expectSuccess(await repository.changeGroupName(code: groupId, name: "Renamed Trip", context: context), prefix: "swiftdata-rename")
        _ = expectSuccess(await repository.archiveGroup(code: groupId, context: context), prefix: "swiftdata-archive")
        _ = expectSuccess(await repository.unarchiveGroup(code: groupId, context: context), prefix: "swiftdata-unarchive")

        expectFailure(await repository.joinGroup(code: "ABCD", context: context), kind: .authenticationRequired, prefix: "swiftdata-join-auth")
        expectFailure(await repository.invite(code: groupId, userIds: ["remote-user"], context: context), kind: .authenticationRequired, prefix: "swiftdata-invite-auth")
        expectFailure(await repository.searchUsers(name: "Wei", context: context), kind: .authenticationRequired, prefix: "swiftdata-search-users-auth")

        let beforeDelete = expectSuccess(await repository.groups(page: 1, pageSize: 10, search: nil, context: context), prefix: "swiftdata-before-delete")
        expect(beforeDelete.items.count, equals: 1, prefix: "swiftdata-before-delete-count")
        _ = expectSuccess(await repository.deleteGroup(code: groupId, context: context), prefix: "swiftdata-delete-group")
        let afterDelete = expectSuccess(await repository.groups(page: 1, pageSize: 10, search: nil, context: context), prefix: "swiftdata-after-delete")
        expect(afterDelete.items.count, equals: 0, prefix: "swiftdata-after-delete-count")
    }

    private static func verifyPersistentStoreSurvivesRecreation() async {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("walkcalc-swiftdata-ledger-\(UUID().uuidString)", isDirectory: true)
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer {
            try? FileManager.default.removeItem(at: directory)
        }
        let storeURL = directory.appendingPathComponent("LocalLedger.store")
        let owner = Member(uuid: "persist-owner", name: "Me", avatar: "", debtMinor: "0", costMinor: "0")
        let context = LedgerSessionContext.local(owner: owner)

        do {
            let firstSource = try SwiftDataLedgerDataSource.temporaryPersistentStore(url: storeURL)
            let firstRepository = LedgerRepository(remoteSource: InMemoryLedgerDataSource(), localSource: firstSource)
            let groupId = expectSuccess(await firstRepository.createGroup(name: "Persisted Trip", context: context), prefix: "swiftdata-persist-create").value ?? ""
            let guestId = expectSuccess(await firstRepository.addTempUser(code: groupId, name: "Guest", context: context), prefix: "swiftdata-persist-temp").value ?? ""
            _ = expectSuccess(await firstRepository.addRecord(groupId: groupId, who: owner.uuid, paidMinor: "900", forWhom: [owner.uuid, guestId], type: "food", text: "Train", long: "", lat: "", occurredAt: 1_710_000_000_000, context: context), prefix: "swiftdata-persist-record")
        } catch {
            fail("swiftdata-persist-first-source threw \(error)")
        }

        do {
            let secondSource = try SwiftDataLedgerDataSource.temporaryPersistentStore(url: storeURL)
            let secondRepository = LedgerRepository(remoteSource: InMemoryLedgerDataSource(), localSource: secondSource)
            let home = expectSuccess(await secondRepository.home(page: 1, pageSize: 10, search: "Persisted", context: context), prefix: "swiftdata-persist-home")
            expect(home.groups.count, equals: 1, prefix: "swiftdata-persist-home-count")
            expect(home.groups.first?.name, equals: Optional("Persisted Trip"), prefix: "swiftdata-persist-name")
            let groupId = home.groups.first?.id ?? ""
            let detail = expectSuccess(await secondRepository.groupDetail(groupId: groupId, recordPageSize: 10, context: context), prefix: "swiftdata-persist-detail")
            expect(detail.records.count, equals: 1, prefix: "swiftdata-persist-record-count")
            expect(detail.group?.allMembers.count, equals: Optional(2), prefix: "swiftdata-persist-member-count")
        } catch {
            fail("swiftdata-persist-second-source threw \(error)")
        }
    }

    private static func expectNoThrow<Value>(_ work: () throws -> Value, prefix: String) -> Value {
        do {
            return try work()
        } catch {
            fatalError("Verification failed [\(prefix)]: threw \(error)")
        }
    }

    private static func expectSuccess<Value>(_ result: LedgerOperationResult<Value>, prefix: String) -> Value {
        switch result {
        case .success(let value):
            return value
        case .failure(let failure):
            fatalError("Verification failed [\(prefix)]: expected success, got \(failure.kind) \(failure.message ?? "")")
        }
    }

    private static func expectFailure<Value>(_ result: LedgerOperationResult<Value>, kind: LedgerOperationFailureKind, prefix: String) {
        switch result {
        case .success:
            fatalError("Verification failed [\(prefix)]: expected failure \(kind), got success")
        case .failure(let failure):
            expect(failure.kind, equals: kind, prefix: prefix)
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
